#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/ioctl.h>

#define SIOCSIWSCAN  0x8B18
#define SIOCGIWSCAN  0x8B19
#define SIOCGIWNAME  0x8B01
#define SCAN_BUFSZ 32768

struct iw_point_u { void *pointer; unsigned short length; unsigned short flags; };
struct iwreq_u { char ifrn_name[16]; union { struct iw_point_u data; char pad[32]; } u; };

int main(int argc,char**argv){
    const char *ifn = argc>1?argv[1]:"wlan2";
    struct iwreq_u w;
    int s=socket(AF_INET,SOCK_DGRAM,0);
    if(s<0){perror("socket");return 1;}
    memset(&w,0,sizeof w); strncpy(w.ifrn_name,ifn,15);
    if(ioctl(s,SIOCGIWNAME,&w)!=0){printf("IWNAME fail\n");close(s);return 1;}

    memset(&w,0,sizeof w); strncpy(w.ifrn_name,ifn,15);
    if(ioctl(s,SIOCSIWSCAN,&w)<0){printf("SCAN fail %s\n",strerror(errno));close(s);return 2;}

    static char buf[SCAN_BUFSZ];
    memset(&w,0,sizeof w); strncpy(w.ifrn_name,ifn,15);
    w.u.data.pointer=buf; w.u.data.length=SCAN_BUFSZ;
    if(ioctl(s,SIOCGIWSCAN,&w)<0){printf("GET fail %s\n",strerror(errno));close(s);return 3;}

    int n=(int)w.u.data.length;
    printf("bytes=%d\n",n);
    unsigned char *p=(unsigned char*)buf;
    for(int i=0;i<n;i++){
        if(i%16==0) printf("\n%04x: ",i);
        printf("%02x ",p[i]);
    }
    printf("\n");
    close(s);
    return 0;
}
