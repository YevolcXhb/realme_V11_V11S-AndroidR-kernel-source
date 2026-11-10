#!/usr/bin/env python3
"""Compile actual patched C functions in portable mocked policy harnesses.
This verifies branch/error/default logic, NOT a kernel build or hardware behavior.
"""
import os,re,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent

def function(path,name):
    text=(ROOT/path).read_text()
    match=re.search(r'(?:static\s+)?(?:void|bool|int)\s+'+re.escape(name)+r'\s*\([^;{}]*\)\s*\{',text)
    if not match:raise ValueError('Function not found: '+name)
    start=match.start();i=match.end()-1;depth=0;state='code'
    while i<len(text):
        ch=text[i];pair=text[i:i+2]
        if state=='code':
            if pair=='/*':state='comment';i+=2;continue
            if pair=='//':state='line';i+=2;continue
            if ch=='"':state='string'
            elif ch=="'":state='char'
            elif ch=='{':depth+=1
            elif ch=='}':
                depth-=1
                if depth==0:return text[start:i+1]
        elif state=='comment':
            if pair=='*/':state='code';i+=2;continue
        elif state=='line':
            if ch=='\n':state='code'
        elif ch=='\\':i+=2;continue
        elif (state=='string' and ch=='"') or (state=='char' and ch=="'"):state='code'
        i+=1
    raise ValueError('Unbalanced function: '+name)

def compile_run(name,source,defines=()):
    compiler=os.environ.get('HOSTCC') or shutil.which('gcc') or shutil.which('cc')
    if not compiler:raise SystemExit('A host C compiler is required for policy tests')
    # All scratch paths remain under this checkout; no system or phone access.
    test_root=ROOT/'ci/_test_work';test_root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=name+'_',dir=test_root) as tmp:
        tmp=Path(tmp).resolve();assert tmp.is_relative_to(test_root.resolve())
        c=tmp/'test.c';exe=tmp/('test.exe' if os.name=='nt' else 'test')
        c.write_text(source,encoding='ascii')
        command=[compiler,'-std=gnu11','-Wall','-Wextra','-Werror','-Wno-unused-parameter',*defines,str(c),'-o',str(exe)]
        subprocess.run(command,check=True,capture_output=True)
        result=subprocess.run([str(exe)],check=True,capture_output=True)
        print(name+': '+result.stdout.decode().strip())

COMMON=r"""
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <errno.h>
#define READ_ONCE(x) (x)
#define WRITE_ONCE(x,v) ((x)=(v))
#define DBG(...) do {} while (0)
#define pr_info(...) do {} while (0)
"""

def rates():
    body=function('kernel/sched/cpufreq_schedutil.c','sugov_init_rate_limits')
    source=COMMON+r"""
#define max(a,b) ((a)>(b)?(a):(b))
struct sugov_tunables { unsigned int up_rate_limit_us,down_rate_limit_us; };
"""+body+r"""
int main(void) {
    struct sugov_tunables t;
    sugov_init_rate_limits(&t,1000);
#ifdef CONFIG_MTK_SERVER_SCHEDUTIL
    assert(t.up_rate_limit_us==(1000>CONFIG_MTK_SERVER_SCHEDUTIL_UP_RATE_US?1000:CONFIG_MTK_SERVER_SCHEDUTIL_UP_RATE_US));
    assert(t.down_rate_limit_us>=t.up_rate_limit_us);
    assert(t.down_rate_limit_us>=CONFIG_MTK_SERVER_SCHEDUTIL_DOWN_RATE_US);
#else
    assert(t.up_rate_limit_us==1000 && t.down_rate_limit_us==1000);
#endif
    sugov_init_rate_limits(&t,50000);
    assert(t.up_rate_limit_us==50000 && t.down_rate_limit_us==50000);
    sugov_init_rate_limits(&t,0);
#ifdef CONFIG_MTK_SERVER_SCHEDUTIL
    assert(t.up_rate_limit_us>0 && t.down_rate_limit_us>=t.up_rate_limit_us);
#else
    assert(t.up_rate_limit_us==0 && t.down_rate_limit_us==0);
#endif
    puts("DVFS initial defaults/hardware bound/stock behavior passed");return 0;
}
"""
    compile_run('schedutil_stock',source)
    compile_run('schedutil_server',source,('-DCONFIG_MTK_SERVER_SCHEDUTIL','-DCONFIG_MTK_SERVER_SCHEDUTIL_UP_RATE_US=2000','-DCONFIG_MTK_SERVER_SCHEDUTIL_DOWN_RATE_US=20000'))
    compile_run('schedutil_inverted_limits',source,('-DCONFIG_MTK_SERVER_SCHEDUTIL','-DCONFIG_MTK_SERVER_SCHEDUTIL_UP_RATE_US=30000','-DCONFIG_MTK_SERVER_SCHEDUTIL_DOWN_RATE_US=1000'))

def usb():
    path='drivers/misc/mediatek/usb20/mt6833/usb20_host.c'
    names=['mt_usb_host_connect','mt_usb_host_disconnect','mt_usb_vbus_on','mt_usb_vbus_off','mt_usb_host_work_requested','otg_tcp_notifier_call','do_vbus_work']
    bodies='\n'.join(function(path,name) for name in names)
    source=COMMON+r"""
#define NOTIFY_DONE 0
#define NOTIFY_OK 1
#define PD_ROLE_UFP 0
#define PD_ROLE_DFP 1
#define TCP_NOTIFY_SOURCE_VBUS 10
#define TCP_NOTIFY_TYPEC_STATE 11
#define TCP_NOTIFY_DR_SWAP 12
#define TCP_NOTIFY_PR_SWAP 13
#define TYPEC_UNATTACHED 0
#define TYPEC_ATTACHED_SRC 1
#define TYPEC_ATTACHED_SNK 2
#define TYPEC_ATTACHED_CUSTOM_SRC 3
#define TYPEC_ATTACHED_NORP_SRC 4
#define CONNECTION_OPS_CONN 1
#define CONNECTION_OPS_DISC 0
#define VBUS_OPS_ON 1
#define VBUS_OPS_OFF 0
struct notifier_block { int unused; };
struct tcp_notify { struct { int mv; } vbus_state; struct { int old_state,new_state; } typec_state; struct { int new_role; } swap_state; };
struct work_struct { int unused; };
struct mt_usb_work { int ops; } queued_work;
#define container_of(ptr,type,member) (&queued_work)
static void kfree(void *p) {}
static int controller;
static void *mtk_musb=&controller;
static bool typec_req_host,typec_req_vbus,boost;
static unsigned int typec_control=1;
static int gadget_connects,gadget_disconnects,vbus_requests,host_requests;
static bool in_uart_mode;
static void usb_phy_switch_to_usb(void) { in_uart_mode=false; }
static void issue_host_work(int ops,int delay,bool on_st) { host_requests++; }
static void issue_vbus_work(int ops,int delay) { vbus_requests++; }
static void mt_usb_connect(void) { gadget_connects++; }
static void mt_usb_disconnect(void) { gadget_disconnects++; }
static void _set_vbus(bool on) { boost=on; }
"""+bodies+r"""
int main(void) {
    struct tcp_notify n={0};struct work_struct work={0};
    /* DFP negotiation before gadget/HCD activation must not be ignored. */
    n.swap_state.new_role=PD_ROLE_DFP;
    assert(otg_tcp_notifier_call(NULL,TCP_NOTIFY_DR_SWAP,&n)==NOTIFY_OK);
    assert(typec_req_host && host_requests==1 && gadget_disconnects==1);
    assert(!boost && vbus_requests==0); /* DFP + power sink must not source. */
    n.swap_state.new_role=PD_ROLE_UFP;
    otg_tcp_notifier_call(NULL,TCP_NOTIFY_DR_SWAP,&n);
    assert(!typec_req_host && gadget_connects==1 && host_requests==2);
    n.swap_state.new_role=999;otg_tcp_notifier_call(NULL,TCP_NOTIFY_DR_SWAP,&n);
    assert(host_requests==2);
    n.swap_state.new_role=PD_ROLE_DFP;otg_tcp_notifier_call(NULL,TCP_NOTIFY_PR_SWAP,&n);
    assert(!typec_req_host && host_requests==2); /* Power swap cannot change data. */
    for (int old=TYPEC_ATTACHED_SRC;old<=TYPEC_ATTACHED_NORP_SRC;old++) {
        typec_req_host=true;n.typec_state.old_state=old;n.typec_state.new_state=TYPEC_UNATTACHED;
        otg_tcp_notifier_call(NULL,TCP_NOTIFY_TYPEC_STATE,&n);assert(!typec_req_host);
    }
    n.typec_state.old_state=TYPEC_UNATTACHED;n.typec_state.new_state=TYPEC_ATTACHED_SRC;
    otg_tcp_notifier_call(NULL,TCP_NOTIFY_TYPEC_STATE,&n);assert(typec_req_host);
    typec_req_host=false;assert(!mt_usb_host_work_requested(true));
    typec_req_host=true;assert(mt_usb_host_work_requested(false));
    typec_control=0;assert(mt_usb_host_work_requested(true));assert(!mt_usb_host_work_requested(false));
    /* A superseded VBUS on/off worker uses the latest power request. */
    n.vbus_state.mv=5000;otg_tcp_notifier_call(NULL,TCP_NOTIFY_SOURCE_VBUS,&n);assert(typec_req_vbus);
    n.vbus_state.mv=0;otg_tcp_notifier_call(NULL,TCP_NOTIFY_SOURCE_VBUS,&n);queued_work.ops=VBUS_OPS_ON;
    do_vbus_work(&work);assert(!boost);
    mt_usb_vbus_on(0);queued_work.ops=VBUS_OPS_OFF;do_vbus_work(&work);assert(boost);
    assert(otg_tcp_notifier_call(NULL,TCP_NOTIFY_DR_SWAP,NULL)==NOTIFY_DONE);
    mtk_musb=NULL;assert(otg_tcp_notifier_call(NULL,TCP_NOTIFY_DR_SWAP,&n)==NOTIFY_DONE);
    in_uart_mode=true;usb_phy_switch_to_usb();assert(!in_uart_mode);
    puts("Type-C data/power separation, detach and stale work passed");return 0;
}
"""
    compile_run('usb_pd_notifier',source)
    compile_run('usb_pd_notifier_uart',source,('-DCONFIG_MTK_UART_USB_SWITCH',))
    original=(ROOT/path).read_text()
    assert 'host_on = mt_usb_host_work_requested(work->ops ==' in original
    assert 'vbus_control = 0;' in original

def role_errors():
    path='drivers/misc/mediatek/typec/tcpc/tcpci_dual_role.c'
    source=COMMON+r"""
#define PD_ROLE_SOURCE 1
#define PD_ROLE_SINK 0
#define PD_ROLE_DFP 1
#define PD_ROLE_UFP 0
#define PD_ROLE_VCONN_OFF 0
#define PD_ROLE_VCONN_ON 1
#define TCPM_ERROR_NO_PD_CONNECTED -42
#define DUAL_ROLE_PROP_PR_SRC 1
#define DUAL_ROLE_PROP_PR_SNK 2
#define DUAL_ROLE_PROP_DR_HOST 1
#define DUAL_ROLE_PROP_DR_DEVICE 2
#define DUAL_ROLE_PROP_VCONN_SUPPLY_NO 1
#define DUAL_ROLE_PROP_VCONN_SUPPLY_YES 2
#include <stdint.h>
enum dual_role_property { DUAL_ROLE_PROP_PR,DUAL_ROLE_PROP_DR,DUAL_ROLE_PROP_VCONN_SUPPLY,DUAL_ROLE_PROP_MODE };
struct tcpc_device { unsigned int dual_role_pr,dual_role_dr,dual_role_vconn,dual_role_mode; } chip;
struct dual_role_phy_instance { struct { void *parent; } dev; } phy;
static void *dev_get_drvdata(void *parent) {return &chip;}
static int pd_result=-EIO,typec_result=-EAGAIN,requests;
#ifdef CONFIG_USB_POWER_DELIVERY
static int tcpm_dpm_pd_power_swap(struct tcpc_device *c,uint8_t r,void *p) {requests++;return pd_result;}
static int tcpm_dpm_pd_data_swap(struct tcpc_device *c,uint8_t r,void *p) {requests++;return pd_result;}
static int tcpm_dpm_pd_vconn_swap(struct tcpc_device *c,uint8_t r,void *p) {requests++;return pd_result;}
#endif
static int tcpm_typec_role_swap(struct tcpc_device *c) {requests++;return typec_result;}
"""
    source+='\n#ifdef CONFIG_USB_POWER_DELIVERY\n'+'\n'.join(function(path,'tcpc_dual_role_set_prop_'+n) for n in ['pr','dr','vconn'])+'\n#else\n'+function(path,'tcpc_dual_role_set_prop_mode')+'\n#endif\n'+function(path,'tcpc_dual_role_set_prop')
    source+=r"""
int main(void) {
    unsigned int value=1;
#ifdef CONFIG_USB_POWER_DELIVERY
    assert(tcpc_dual_role_set_prop(&phy,DUAL_ROLE_PROP_DR,&value)==-EIO);
    assert(tcpc_dual_role_set_prop(&phy,DUAL_ROLE_PROP_PR,&value)==-EIO);
    assert(tcpc_dual_role_set_prop(&phy,DUAL_ROLE_PROP_VCONN_SUPPLY,&value)==-EIO);
    assert(requests==3);
    pd_result=TCPM_ERROR_NO_PD_CONNECTED;
    assert(tcpc_dual_role_set_prop(&phy,DUAL_ROLE_PROP_PR,&value)==-EAGAIN);
    assert(requests==5);
    value=999;assert(tcpc_dual_role_set_prop(&phy,DUAL_ROLE_PROP_DR,&value)==-EINVAL);assert(requests==5);
    value=DUAL_ROLE_PROP_DR_HOST;chip.dual_role_dr=value;
    assert(tcpc_dual_role_set_prop(&phy,DUAL_ROLE_PROP_DR,&value)==0);assert(requests==5);
#else
    (void)pd_result;
    assert(tcpc_dual_role_set_prop(&phy,DUAL_ROLE_PROP_MODE,&value)==-EAGAIN);
    assert(requests==1);
#endif
    assert(tcpc_dual_role_set_prop(&phy,(enum dual_role_property)999,&value)==-EINVAL);
    puts("PD/Type-C request errors reach the caller; no false success passed");return 0;
}
"""
    compile_run('tcpc_pd_error_propagation',source,('-DCONFIG_USB_POWER_DELIVERY',))
    compile_run('tcpc_typec_error_propagation',source)

def main():
    rates();usb();role_errors()
    print('7 actual-function C harness variants passed; no kernel/hardware claim.')
if __name__=='__main__':
    try:main()
    except subprocess.CalledProcessError as e:
        if e.stdout:print(e.stdout.decode(errors='replace'))
        if e.stderr:print(e.stderr.decode(errors='replace'))
        raise
