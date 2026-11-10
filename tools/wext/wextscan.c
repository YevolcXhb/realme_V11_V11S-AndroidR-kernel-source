#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/ioctl.h>

#define SIOCSIWSCAN 0x8B18
#define SIOCGIWSCAN 0x8B19
#define SIOCGIWNAME 0x8B01
#define SIOCGIWAP   0x8B15
#define SIOCGIWESSID 0x8B1B

struct iw_point_u { void *pointer; unsigned short length; unsigned short flags; };
struct iwreq_u { char ifrn_name[16]; union { struct iw_point_u data; char pad[32]; } u; };
#define LCP 4

static const char *evname(int id){
    switch(id){
    case 0x8B15: return "SIOCGIWAP";
    case 0x8B1B: return "SIOCGIWESSID";
    case 0x8B1F: return "SIOCGIWFREQ";
    case 0x8B21: return "SIOCGIWMODE";
    case 0x8B29: return "SIOCGIWENCODE";
    case 0x8B2B: return "SIOCGIWRATE";
    case 0x8C00: return "IWEVCUSTOM";
    case 0x8C01: return "IWEVASSOCREQIE";
    case 0x8C02: return "IWEVASSOCRESPIE";
    case 0x8C04: return "IWEVGENIE";
    default: return "event";
    }
}

int main(int argc,char**argv){
    const char *ifn = argc>1?argv[1]:"wlan2";
    struct iwreq_u w;
    int s=socket(AF_INET,SOCK_DGRAM,0);
    if(s<0){perror("socket");return 1;}

    memset(&w,0,sizeof w); strncpy(w.ifrn_name,ifn,15);
    if(ioctl(s,SIOCGIWNAME,&w)==0) printf("IWNAME ok\n");
    else printf("IWNAME fail %s\n",strerror(errno));

    /* TRIGGER: report the real return value, not just "accepted" */
    memset(&w,0,sizeof w); strncpy(w.ifrn_name,ifn,15);
    errno=0;
    int rc=ioctl(s,SIOCSIWSCAN,&w);
    printf("SIWSCAN rc=%d errno=%d (%s)\n", rc, errno, strerror(errno));
    if(rc<0){ close(s); return 2; }

    /* GET: call it a few times, print what each attempt returns */
    char *buf=malloc(256*1024);
    int best=-1;
    for(int i=0;i<8;i++){
        memset(&w,0,sizeof w); strncpy(w.ifrn_name,ifn,15);
        w.u.data.pointer=buf; w.u.data.length=256*1024; w.u.data.flags=0;
        errno=0;
        int r=ioctl(s,SIOCGIWSCAN,&w);
        printf("  GET[%d] rc=%d errno=%d(%s) len=%u\n",
               i, r, errno, strerror(errno), w.u.data.length);
        if(r==0){ best=(int)w.u.data.length; break; }
        if(errno==EAGAIN){ usleep(400000); continue; }
        break;
    }
    if(best<0){ printf("no results\n"); close(s); free(buf); return 5; }

    printf("\nbytes=%d\n", best);
    int off=0,n=0;
    while(off+LCP<=best){
        unsigned short id,len;
        memcpy(&id,buf+off,2); memcpy(&len,buf+off+2,2);
        if(!len||off+len>best) break;
        if(id==SIOCGIWAP){n++;printf("\n--- BSS %d ---\n",n);}
        printf("  %-16s len=%u",evname(id),len);
        if(id==SIOCGIWAP){unsigned char*p=(unsigned char*)(buf+off);printf(" MAC");
            for(int k=0;k<6;k++)printf(":%02x",p[LCP+2+k]);}
        else if(id==SIOCGIWESSID){unsigned char*p=(unsigned char*)(buf+off);printf(" \"");
            for(int k=LCP;k<len;k++) if(p[k]>=0x20&&p[k]<0x7f) putchar(p[k]);
            printf("\"");}
        printf("\n");
        off+=len;
    }
    printf("\ntotal BSS: %d\n",n);
    close(s);free(buf);return n>0?0:6;
}
