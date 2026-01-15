#include <error.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>
#include <sys/time.h>
#include <signal.h>
#include <stdbool.h>
#include <sys/stat.h>
#include <linux/input.h>
#include <pthread.h>

#define BRIDGE 0xC0000000
#define BRIDGE2 0xC0000080
#define BRIDGE_SPAN 0x88

#define SD_DATA 0x0000
#define SD_DATA_OP 0x0010
#define SD_HPS_REQID 0x0020
#define SD_CMD 0x0030
#define SD_ARG1 0x0040
#define SD_DEBUG_INFO 0x0050
#define GAMEPAD 0x0080
#define FILER 0x0084

#define QUEUE_SIZE 16

static volatile int keepRunning = 1;

static volatile uint8_t* sdop_map = NULL;
static volatile uint8_t* sddata_map = NULL;
static volatile uint8_t* sdreqId_map = NULL;
static volatile uint16_t hps_reqId=0;

/***** Commandes FPGA *****
 * File for test: mario-mono.dat
 * 1: Get number files in music directory
 * 2: Get names of files
 * 3: Open file and start read 2 chars or continue reading
 * 31: Open file and start read 1 char or continue reading
 * 4: Close file
 * 5: Stop All
 * 6: Get number of samples in music file
 ***************************/

/***** Signaux HPS *****
 * 1: SD Card ready
 * 2: Return number of wave files in directory "/root/music"
 * 3: Return size of given file
 * 5: Return 2 chars from file content
 * 7: Waiting for new request
 * 8: Return file size
 * 9: Return 1 char from file content
 * 10: Return 4 chars from file content
 ************************/

void intHandler(int dummy) {
    keepRunning = 0;
}

typedef struct {
    size_t head;
    size_t tail;
    size_t size;
    void** data;
} queue_t;

size_t queue_count(queue_t *queue) {
	return queue->head - queue->tail;
}

void* queue_read(queue_t *queue) {
    if (queue->tail == queue->head) {
        return NULL;
    }
    void* handle = queue->data[queue->tail];
    queue->data[queue->tail] = NULL;
    queue->tail = (queue->tail + 1) % queue->size;
    return handle;
}

int queue_write(queue_t *queue, void* handle) {
    if (((queue->head + 1) % queue->size) == queue->tail) {
        return -1;
    }
    queue->data[queue->head] = handle;
    queue->head = (queue->head + 1) % queue->size;
    return 0;
}

void setMapValue(int map_ptr,int map_value,bool upReqId) {
    if(map_ptr == 0) *((uint16_t *)sdop_map) = (uint16_t) map_value;
    else if(map_ptr == 1) *((uint32_t *)sddata_map) = map_value;
    else printf("setMapValue impossible for map_ptr %d\n",map_ptr);

    if(upReqId){
    	hps_reqId++;
		*((uint16_t *)sdreqId_map) = hps_reqId;
    }
}

void *thread_gamepad(void *data) {
	pthread_t tid;
	////queue_t* queue_gamepad = (queue_t *)data;
	uint8_t* gamepad_map = (uint8_t *)data;

	// La fonction pthread_self() renvoie
	// l'identifiant propre à ce thread.
	tid = pthread_self();
	printf("Thread [%lu] running\n",(unsigned long)tid);

	//Process for Gamepad
	int fd2 = open("/dev/input/event0",O_RDONLY);
	if(fd2 < 0){
		perror("Couldnt open event0.");
		return (NULL);
	}

	ssize_t bytes;
	struct input_event ev;
	int axeVal;
	while(keepRunning){
		bytes = read(fd2, &ev, sizeof(ev));
		if(bytes == sizeof(ev)){
			if(ev.type == EV_KEY){
				printf("Touche %u %s\n", ev.code, ev.value ? "pressée" : "relachée");
				*((uint32_t *)gamepad_map) =  ((1 + 1*ev.value) << 9) + ev.code;//1 + 190 => A pressée / 0 + 190 => A relachée
			}
			else if(ev.type == EV_ABS){
				printf("Axe %u valeur %d\n", ev.code, ev.value);
				axeVal = ev.value;
				if(ev.value < 0) axeVal += 512;
				*((uint32_t *)gamepad_map) = axeVal;
				////queue_write(queue_gamepad, (void*)(ev.value));
			}
		}
	}

	close(fd2);

	printf("Thread [%lu] stopped\n",(unsigned long)tid);

	return (NULL); // Le thread termine ici.
}

int main(int argc, char** argv) {
	//using namespace boost::multiprecision;

	pthread_t tid1; // Identifiant du thread Gamepad

	uint16_t opNum = 0;
	int sddata = 0;
	//uint16_t hps_reqId=0;
	uint16_t fCmd = 0;
	int fArg1 = 0;
	int fDebug = 0;
	int fArg1_cur;
	int gamepad = 0;
	int filer = 0;

	int audios_count = 0;
	int count = 0;
	int fileName_len;
	char filename[256];
	int i;
	char line[10];
	int audio_sample=0;

	fpos_t pos;

	struct dirent *dir;
	struct timeval time;
	struct stat st;
	char filenameSel[64];

	signal(SIGINT, intHandler);

	printf("Display music list\n");

	DIR *d = opendir("/root/music/"); 
	if (d){
		while ((dir = readdir(d)) != NULL) {
			fileName_len = strlen(dir->d_name);

			if(fileName_len > 4){
				if( (dir->d_name[fileName_len - 1] == 'v' && dir->d_name[fileName_len - 2] == 'a')){
					audios_count++;
					printf("%s\n", dir->d_name);
					//printf("name size: %d\n",strlen(dir->d_name));
				}
			}
		}
		closedir(d);
	}

	printf("Music list done\n");
	//usleep(500*1000);

	int fd = 0;

	fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) {
		perror("Couldn't open /dev/mem\n");
		return -2;
	}

	/*int fdG = 0;

	fdG = open("/dev/mem", O_RDWR | O_SYNC);
	if (fdG < 0) {
		perror("Couldn't open 2nd /dev/mem\n");
		return -2;
	}*/

	uint8_t* bridge_map = NULL;

	bridge_map = (uint8_t*)mmap(NULL, BRIDGE_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd, BRIDGE);

	if (bridge_map == MAP_FAILED) {
		perror("Couldn't map bridge.");
		close(fd);
		return -3;
	}

	printf("bridge_map created\n");
	usleep(500*1000);

	//uint8_t* sddata_map = NULL;
	//uint8_t* sdop_map = NULL;
	//uint8_t* sdreqId_map = NULL;
	uint8_t* sdcmd_map = NULL;
	uint8_t* sdarg1_map = NULL;
	uint8_t* sddebug_map = NULL;
	uint8_t* gamepad_map = NULL;
	uint8_t* filer_map = NULL;
	

	sddata_map = bridge_map + SD_DATA;
	sdop_map = bridge_map + SD_DATA_OP;
	sdreqId_map = bridge_map + SD_HPS_REQID;
	sdcmd_map = bridge_map + SD_CMD;
	sdarg1_map = bridge_map + SD_ARG1;
	sddebug_map = bridge_map + SD_DEBUG_INFO;
	gamepad_map = bridge_map + GAMEPAD;
	filer_map = bridge_map + FILER;

	opNum = 1;//1 => sd ready / 2 => Nb files
	int hData=0;
	printf("Press Ctrl + C to quit\n");
	gettimeofday(&time, NULL);
	unsigned long microsec = (time.tv_sec * 1000000) + time.tv_usec;
	printf("start communication ==> %lu\n",microsec);

	int pause_ena;
	uint16_t fCmd_prev;
	int nbRead;

	// Création du premier thread qui va directement aller
	 // exécuter sa fonction thread_gamepad.
	queue_t queue_gamepad = {0, 0, QUEUE_SIZE, (void**)malloc(sizeof(void*) * QUEUE_SIZE)};
	////pthread_create(&tid1, NULL, thread_gamepad, &queue_gamepad);
	pthread_create(&tid1, NULL, thread_gamepad, gamepad_map);
	printf("Main: Creation du thread Gamepad [%lu]\n", (unsigned long)tid1);
	void* gamepadHandle;

	//if(pid_fils > 0){
	if(true){
		// Process for SD Controller
		while(keepRunning){
			setMapValue(0,opNum,0);
			
			if(opNum == 8 || opNum == 2 || opNum == 4){
				//printf("Set to filer_map: %d\n",hData);
				*((int *)filer_map) = hData;
			}
			else{
				//printf("setMapValue: %d\n",hData);
				setMapValue(1,hData,1);
			}

			fCmd = *((uint16_t *)sdcmd_map);
			fArg1 = *((int *)sdarg1_map);
			fDebug = *((int *)sddebug_map);
			
			if(fCmd != 5){
				printf("REQID%d OP%d FCMD : %d / ARG1 : %d / FDEBUG: %d\n",hps_reqId,opNum,fCmd,fArg1,fDebug);
				//printf("FDEBUG : %d\n",fDebug);
			}

			pause_ena = 1000;//ms

			if(fCmd == 1) {//Request to get number of files in music directory
				opNum = 2;
				hData = audios_count;
				printf("GET NUMBER OF FILES : %d\n",audios_count);
				pause_ena = 500;
			}
			else if(fCmd == 2) {//Request to get name of file at given pos
				printf("GET FILENAME NUM : %d\n",fArg1);

		        opNum = 3;
				d = opendir("/root/music/");
				if (d){
					i = 0;
					while ((dir = readdir(d)) != NULL) {
						fileName_len = strlen(dir->d_name);
						if(fileName_len > 4){
							if( (dir->d_name[fileName_len - 1] == 'v' && dir->d_name[fileName_len - 2] == 'a')) {
								if(i == fArg1){
									strcpy(filename,dir->d_name);
									filename[fileName_len] = '\0';
									break;
								}
								i++;
							}
						}
					}
					closedir(d);
				}
				
				gettimeofday(&time, NULL);
				microsec = (time.tv_sec * 1000000) + time.tv_usec;
				printf("start send name %s: %lu\n",filename,microsec);
				for(i=0; i < 100;i++){
					if(filename[i] == '\0'){
						//Avant de sortie, on ajoute un saut de ligne pour l'affichage sur l'écran
						setMapValue(0,i*16 + opNum,0);//i*16 pour decaler 4 fois a gauche
						//setMapValue(1,'\n',1);
						*((int *)filer_map) = '\n';
						
						fCmd = *((uint16_t *)sdcmd_map);
						fDebug = *((int *)sddebug_map);
						//printf("OP3 FCMD : %d\n",fCmd);
						//printf("OP3 FDEBUG : %d\n",fDebug);

						break;
					}

					setMapValue(0,i*16 + opNum,0);
					//setMapValue(1,filename[i],1);
					*((int *)filer_map) = filename[i];

					fCmd = *((uint16_t *)sdcmd_map);
					fDebug = *((int *)sddebug_map);
					//printf("OP3 FCMD : %d\n",fCmd);
					//printf("OP3 FDEBUG : %d\n",fDebug);
				}
				gettimeofday(&time, NULL);
				microsec = (time.tv_sec * 1000000) + time.tv_usec;
				printf("end send name: %lu\n",microsec);

				opNum = 4;//Send signal end filename
				pause_ena = 0;
			}
			else if(fCmd == 3 || fCmd == 31 || fCmd == 34){//Request to get content of file requested
				if(fCmd == 3) opNum = 5;//Send 2 chars from file content
				else if(fCmd == 34) opNum = 10;//Send 4 chars from file content
				else opNum = 9;//Send 1 char from file content

				fDebug=-1;
				nbRead = 0;
				fArg1_cur = -1;
				/*FILE* fp;
				fp = fopen(filenameSel,"r");*/

				int fdFiler = open(filenameSel, O_RDONLY);

				struct stat stFiler;
				fstat(fdFiler, &stFiler);
				size_t sizeFiler = stFiler.st_size;

				char *dataFiler = (char*)mmap(NULL, sizeFiler, PROT_READ, MAP_PRIVATE, fdFiler, 0);

				bool opNumChanged = false;
				//fgetpos(fp,&pos);
				
				gettimeofday(&time, NULL);
				microsec = (time.tv_sec * 1000000) + time.tv_usec;
				printf("start send data audio: %lu\n",microsec);

				*((uint16_t *)sdop_map) = opNum;
				
				while(keepRunning){
					if((fArg1_cur != fArg1) || (opNumChanged)){//Pas très propre, on pourrait faire ça plus proprement en utilisant un 2ème bridge qui serait synchro avec l'horloge de l'audio
						fArg1_cur = fArg1;

						if(opNum == 5){
							/*fseek(fp,fArg1_cur,SEEK_SET);
							count = fread(line,1,2,fp);
							audio_sample = (((int)line[1]) << 8) + (int)line[0];*/
							*((int *)filer_map) = (dataFiler[fArg1_cur + 1] << 8) + dataFiler[fArg1_cur];
						}
						else if(opNum == 10){
							/*fseek(fp,fArg1_cur,SEEK_SET);
							count = fread(line,1,4,fp);
							audio_sample = (((int)line[3]) << 24) + ((int)line[2] << 16) + (((int)line[1]) << 8) + (int)line[0];*/
							*((int *)filer_map) = (dataFiler[fArg1_cur + 1] << 24) + (dataFiler[fArg1_cur + 1] << 16) + (dataFiler[fArg1_cur + 1] << 8) + dataFiler[fArg1_cur];
						}
						else{
							/*fseek(fp,fArg1_cur,SEEK_SET);
							count = fread(line,1,1,fp);
							audio_sample = (int)line[0];*/
							*((int *)filer_map) = dataFiler[fArg1_cur];
						}
						//*((int *)filer_map) = audio_sample;

						/* *((int *)sddata_map) = audio_sample;
						//*((uint16_t *)sdop_map) = opNum;//opNum ne change pas
						hps_reqId++;
						*((uint16_t *)sdreqId_map) = hps_reqId;*/

						fCmd = *((uint16_t *)sdcmd_map);
						fArg1 = *((int *)sdarg1_map);
						//fDebug = *((int *)sddebug_map);

						/*if(fArg1_cur % 10000 == 0){
							printf("value at %d => %s (%d chars)\n",fArg1_cur,line,count);
							printf("value from fpga => %d\n",fDebug);
						}*/
						nbRead++;
					}
					else{//On se met en attente
						//if(nbRead < 400) printf("Waiting - fCmd: %d | fArg1: %d | fDebug: %d\n",fCmd,fArg1,fDebug);//A commenter
						if(nbRead < 400) printf("Waiting - fCmd: %d | fArg1: %d\n",fCmd,fArg1);//A commenter
						//setMapValue(0,opNum,1);//opNum ne change pas
						/* hps_reqId++;
						*((uint16_t *)sdreqId_map) = hps_reqId;//permet au FPGA de relire la précédente donnée quand il se met en attente */
						
						fCmd = *((uint16_t *)sdcmd_map);
						fArg1 = *((int *)sdarg1_map);
						//fDebug = *((int *)sddebug_map);
						//nbRead++;
					}

					if(fCmd == 4) break;

					if(fCmd == 3){//Send 2 chars from file content
						if(opNum != 5){
							opNum = 5;
							*((uint16_t *)sdop_map) = opNum;
							opNumChanged = true;
						}
						else if(opNumChanged) opNumChanged = false;
					}
					else if(fCmd == 34){//Send 4 chars from file content
						if(opNum != 10){
							opNum = 10;
							*((uint16_t *)sdop_map) = opNum;
							opNumChanged = true;
						}
						else if(opNumChanged) opNumChanged = false;
					}
					else opNum = 9;//Send 1 char from file content

					if(nbRead <= 400) printf("opNum: %d | fCmd: %d | fArg1: %d | fDebug: %d\n",opNum,fCmd,fArg1,fDebug);//A commenter
					//if(nbRead <= 400) printf("fCmd: %d | fArg1: %d\n",fCmd,fArg1);//A commenter
				}

				gettimeofday(&time, NULL);
				microsec = (time.tv_sec * 1000000) + time.tv_usec;
				printf("end send data audio: %lu\n",microsec);
				printf("Debug fArg1: %d\n",fArg1);

				//fclose(fp);
				munmap(dataFiler, sizeFiler);
				close(fdFiler);

				opNum = 6;
				pause_ena = 0;
				//*((int *)sddata_map) = 0;
		        //*((uint16_t *)sdop_map) = opNum;
			}
			else if(fCmd == 5){//Pending action
				opNum = 7;//Waiting for new action
				pause_ena = 100;
			}
			else if(fCmd == 6){//Get filesize of selected file
				if(fCmd_prev != fCmd){//On évite de refaire le calcul inutile
					printf("File num requested: %d\n",fArg1);

					memset(filenameSel,0,64);
					strcpy(filenameSel,"/root/music/");

					d = opendir("/root/music/");
					if (d){
						i = 0;
						while ((dir = readdir(d)) != NULL) {
							fileName_len = strlen(dir->d_name);
							if(fileName_len > 4){
								//if(dir->d_name[fileName_len - 1] == 't' && dir->d_name[fileName_len - 2] == 'a'){
								if( (dir->d_name[fileName_len - 1] == 'v' && dir->d_name[fileName_len - 2] == 'a')){
									if(i == fArg1){
										strcat(filenameSel,dir->d_name);
										break;
									}
									i++;
								}
							}
						}
						closedir(d);
					}
					
					stat(filenameSel, &st);
					hData = st.st_size;

					printf("Size of file %s : %d\n",filenameSel,hData);
				}

				opNum = 8;
				pause_ena = 100;

				/**((uint16_t *)sdop_map) = opNum;
				*((int *)sddata_map) = hData;
				hps_reqId++;
				*((uint16_t *)sdreqId_map) = hps_reqId;*/
			}
			else if(fCmd == 9){
				opNum = 11;
				nbRead = 0;
				fArg1_cur = -1;
				
				int fdSpTe = open("/root/music/test-speed.txt", O_RDONLY);

				struct stat stSpTe;
				fstat(fdSpTe, &stSpTe);
				size_t sizeSpTe = stSpTe.st_size;
				int dataTmp;

				char *dataSpTe = (char*)mmap(NULL, sizeSpTe, PROT_READ, MAP_PRIVATE, fdSpTe, 0);
				
				gettimeofday(&time, NULL);
				microsec = (time.tv_sec * 1000000) + time.tv_usec;
				printf("start speed test: %lu\n",microsec);
				
				*((uint16_t *)sdop_map) = opNum;//opNum ne change pas


				while(keepRunning){
					if(fArg1_cur != fArg1){
						fArg1_cur = fArg1;
						*((int *)filer_map) = dataSpTe[fArg1_cur];
						
						//nbRead++;
					}

					fCmd = *((uint16_t *)sdcmd_map);
					fArg1 = *((int *)sdarg1_map);

					if(fCmd == 10){
						break;
					}
					/*else if(fArg1 == 2){
						fDebug = *((int *)sddebug_map);
					}*/
					//if(nbRead > 1300000) break;
				}

				nbRead = fArg1;

				gettimeofday(&time, NULL);
				microsec = (time.tv_sec * 1000000) + time.tv_usec;
				printf("end speed test: %lu\n",microsec);
				//printf("nbRead: %d | fDebug: %d\n",nbRead,fDebug);
				printf("nbRead: %d\n",nbRead);
				//printf("last data: %d\n",dataTmp);

				munmap(dataSpTe, sizeSpTe);
				close(fdSpTe);

				opNum = 6;
				pause_ena = 0;
			}

			//if(hps_reqId >= 46015) break;
			//if(hps_reqId >= 10) break;

			fCmd_prev = fCmd;
			if(pause_ena) usleep(pause_ena*1000);
		}
	}

	int result = munmap(bridge_map, BRIDGE_SPAN);

	if (result < 0) {
	  perror("Couldnt unmap bridge.");
	  close(fd);
	  return -4;
	}
	else{
		printf("Avalon Memory unmapped successfully\n");
	}

	close(fd);


	// Le main thread attend que le thread Gamepad
	// se termine avec pthread_join.
	printf("Press a key on the Gamepad ...\n");

	pthread_join(tid1, NULL);
	printf("Main: Union du premier thread [%lu]\n",(unsigned long)tid1);

	printf("The End ;-)\n");
	return (0);
}

