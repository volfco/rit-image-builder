"""

    builde.py
        --download      Download a file
            --url       The URL
            
        --path          Path to the raw image on the system
        
        --target=openstack
        
        --target=vra
            --vra-server
            --vra-port
            --vra-mgmt-server
            --vra-mgmt-port
            --vra-ignore-ssl    Ignores server's SSL



Tested and Working

NBD / QEMU-NBD
    - Fedora 25
    - Fedora 24
    - openSUSE Leap 42.1
    - CentOS 7.x

GUESTMOUNT
    - Ubuntu 14.04

"""
import os
import uuid
import stat
from subprocess import call
import datetime
from shutil import copyfile
from jinja2 import Environment, FileSystemLoader
import argparse
import pychroot
import logging
import yaml
#import openstack

MNT_DIR = "/mnt/guest"
ISSUE_BANNER = ". RIT Academic Cloud"
DNS = "129.21.3.17"

TYPE = "" # openstack or vra

EPEL_OSS = ['centos', 'fedora']
DEB_OSS = ['debian', 'ubuntu']
SUSE_OSS = ['opensuse']

# functions
def writeFile(fh, contents):
    fh = open(fh, 'w')
    fh.write(contents)
    fh.close()

def sourceFile(filepath):
    fh = open(filepath, 'r')
    rtn = {}
    for line in fh.readlines():
        ln = line.split("=")
        rtn[ln[0]] = ln[1].replace("\"", "").strip()
    fh.close()
    return rtn

def findLineAppend(filepath, search, append, all=True):
    fh = open(filepath, 'r')
    lines = []
    hit = False
    for line in fh.readlines():
        tl = line.rstrip()
        if search in line and not hit:
            tl += " " + append
            if all is not True:
                hit = True
        lines.append(tl)
    fh.close()
    fhw = open(filepath, 'w')
    print("\n".join(lines))
    fhw.write("\n".join(lines))
    fhw.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='')
    parser.add_argument('--download', action='store_true')
    parser.add_argument('--url', required=False)

    parser.add_argument('--path')
    parser.add_argument('--target')

    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO)

    if not args.path and not args.download:
        print('invalid usage')
        exit(1)

    PATH = os.path.dirname(os.path.abspath(__file__))
    TEMPLATE_ENVIRONMENT = Environment(autoescape=False, loader=FileSystemLoader(os.path.join(PATH, 'components')), trim_blocks=False)
    FNULL = open(os.devnull, 'w')
    
    if args.download:
        file_path = "/tmp/" + file_name

    else:
        file_path = args.path

    #logging.info("== Making sure nbd is loaded ====================")
    #mbr = call(["/usr/sbin/modprobe", "nbd", "max_part=8"])
    #if mbr is not 0:
    #    logging.critical("ERROR Unable to load nbd module into the kernel. Am I root?")
    #    exit(1)

    #logging.info("== Mounting Guest ===============================")
    #NBDFound = False
    #for i in range(0, 15):
    #    NBDDevice = "/dev/nbd{0}".format(i)
#
    #    if not os.path.exists(NBDDevice):
    #         logging.warning("Unable to locate " + NBDDevice)
    #    else:
    #        nbdr = call(["qemu-nbd", "--connect", NBDDevice, file_path], stderr=FNULL)
    #        if nbdr is not 0:
    #            logging.warning("Unable to use " + NBDDevice)
    #        else:
    #            logging.info("Using " + NBDDevice)
    #            NBDFound = True
    #            break

    #if not NBDFound:
    #     logging.critical("Unable to find a usable NDB Device. Try rebooting.")
    #     exit(1)

    #partition = NBDDevice + "p1"
    #if not os.path.exists(partition):
    #    logging.critical(partition + " Does not exist")
    #    call(["qemu-nbd", "--disconnect", NBDDevice])   # Cleanup
    #    exit(1)

    logging.info("== Generating UUID ==============================")
    UUID = str(uuid.uuid4())
    logging.info("UUID Is: " + UUID)

    logging.info("== Copying to /tmp ==============================")
    new_file_path = os.path.basename(file_path).split(".")
    new_file_path[-1] = "{0}.{1}".format(UUID, new_file_path[-1])
    new_file_path = "/tmp/" + ".".join(new_file_path)

    logging.info("Source: " + file_path)
    logging.info("Destination: " + new_file_path)

    copyfile(file_path, new_file_path)

    file_path = new_file_path

    logging.info("== Mounting Guest ===============================")
    #call(['e2fsck', '-f', partition])
    #mntr = call(["mount", partition, MNT_DIR])
    #if mntr is not 0:
    #    logging.critical("Unable to mound device. Am I Root?")
    #    call(["qemu-nbd", "--disconnect", NBDDevice])
    #    exit(1)
    mntr = call(["guestmount", "-i", "-w", "-a", file_path, MNT_DIR])
    if mntr is not 0:
        logging.critical("Unable to mound device. Am I Root?")
        exit(1)

    logging.info("== Figuring OS Type =============================")
    if os.path.exists("{0}/etc/redhat-release".format(MNT_DIR)):    # CentOS, EPEL, Fedora, Scientifc 
        release_fh = open("{0}/etc/redhat-release".format(MNT_DIR), 'r')
        release = release_fh.read().split(' ')[0].lower()
        release_fh.close()
    elif os.path.exists("{0}/etc/lsb-release".format(MNT_DIR)):
        os_data = sourceFile("{0}/etc/lsb-release".format(MNT_DIR))
        release = os_data['DISTRIB_ID'].lower()
    elif os.path.exists("{0}/etc/os-release".format(MNT_DIR)):  # OpenSUSE 
        os_data = sourceFile("{0}/etc/os-release".format(MNT_DIR))
        release = os_data['NAME'].lower().split(" ")[0]
    else:
        logging.warning("OS is not supported")
        exit(0)

    logging.info("OS Release", release)
        
    logging.info("== Writing resolv.conf ==========================")
    # UBUNTU 16.04 ../run/resolvconf/resolv.conf
    call(["mv", "{0}/etc/resolv.conf".format(MNT_DIR), "{0}/etc/resolv.conf.old".format(MNT_DIR)])
    writeFile("{0}/etc/resolv.conf".format(MNT_DIR),"nameserver {0}\n".format(DNS))

    logging.info("== Writing issue file ===========================")
    BUILDTIME = str(datetime.datetime.now().strftime("%Y-%m-%d"))
    issue = "\S{0}\nKernel      \\r\nBuild Date  {1} ({2})\n\n".format(ISSUE_BANNER, BUILDTIME, UUID)
    writeFile("{0}/etc/issue".format(MNT_DIR), issue)
    writeFile("{0}/BUILD.txt".format(MNT_DIR), UUID)

    logging.info("== Copying SSL CA Certificates ==================")
    # Copy SSL Certificates
    if os.path.exists("{0}/usr/local/share/ca-certificates/".format(MNT_DIR)):
        cert_path = "/usr/local/share/ca-certificates/"
    elif os.path.exists("{0}/etc/pki/ca-trust/source/anchors/".format(MNT_DIR)):
        cert_path = "/etc/pki/ca-trust/source/anchors/"
    elif os.path.exists("{0}/usr/share/pki/trust/".format(MNT_DIR)):
        cert_path = "/usr/share/ca-certificates/"

    for cert in ['rit-bundle.cer', 'rit-ac-bundle.cer']:
        logging.debug("Copying: ", cert, "{0}/{1}/{2}".format(MNT_DIR, cert_path, cert))
        copyfile('./components/' + cert, "{0}/{1}/{2}".format(MNT_DIR, cert_path, cert))
     
    logging.info("== Copying vRA Installer ========================")
    if args.target == "vra":
        copyfile('./components/prepare_vra_template.sh', "{0}/tmp/vra.sh".format(MNT_DIR))
    else:
        logging.info("Skipping")

    logging.info("== Generating boot.sh ===========================")
    #
    if release in EPEL_OSS or release in DEB_OSS:
        username = release
    else:
        username = 'root'
    logging.info("Username is: " + username)

    if os.path.exists("{0}/bin/update-ca-trust".format(MNT_DIR)):
        CACommand = "/bin/update-ca-trust"
    elif os.path.exists("{0}/usr/bin/update-ca-trust".format(MNT_DIR)):
        CACommand = "/usr/bin/update-ca-trust"
    else:
        CACommand = "/usr/sbin/update-ca-certificates"

    logging.info("CA Store Update Command: " + CACommand)
    BOOTFILE = TEMPLATE_ENVIRONMENT.get_template('boot.tmpl.sh').render(release=release, username=username, password=release)

    logging.info("== Chrooting into image =========================")
    with pychroot.Chroot(MNT_DIR):

        logging.info("c= Removing Selinux (EPEL) ======================")
        if release in EPEL_OSS:
            call(["/usr/bin/yum", "-y", "remove", "selinux*"])
        else:
            logging.info("!! Skipping !!")

        logging.info("c= Installing Packages ==========================")
        if release in EPEL_OSS:
            pkgs = ["open-vm-tools", "NetworkManager"]
            call(["/usr/bin/yum", "-y", "install"] + pkgs)
        elif release in DEB_OSS:
            pkgs = ["open-vm-tools", "rng-tools"]
            call(["/usr/bin/apt-get", "-y", "install"] + pkgs)
        elif release in SUSE_OSS:
            pkgs = ['open-vm-tools', 'NetworkManager']
            call(["/usr/bin/zypper", "--non-interactive", "install"] + pkgs)

        logging.info("c= Installing Cloud-Init ========================")
        if args.target == "openstack":
            if release in EPEL_OSS:
                pkgs = ["cloud-init", "cloud-utils", "cloud-utils-growpart"]
                call(["/usr/bin/yum", "-y", "install"] + pkgs)
            elif release in SUSE_OSS:
                pkgs = ["cloud-init"]
                call(["/usr/bin/zypper", "--non-interactive", "install"] + pkgs)
            elif release in DEB_OSS:
                pkgs = ["cloud-utils-euca", "cloud-init"]
                # https://bugs.launchpad.net/ubuntu/+source/aptitude/+bug/1543280/comments/20
                call(['chown', '_apt', '/var/lib/update-notifier/package-data-downloads/partial/'])
                call(['/usr/bin/apt-get', '-y', 'install'] + pkgs)
            logging.debug(pkgs)
        else:
            logging.warning("Skipping")

        logging.info("c= Configuring Cloud-Init =======================")
        if args.target == "openstack":
            logging.debug("writing boot.sh")
            
            try:
                os.makedirs('/var/lib/cloud/scripts/per-once/')
            except Exception:
                logging.debug("Unable to make path")

            writeFile('/var/lib/cloud/scripts/per-once/boot.sh'.format(MNT_DIR), BOOTFILE)
            st = os.stat('/var/lib/cloud/scripts/per-once/boot.sh'.format(MNT_DIR))
            os.chmod('/var/lib/cloud/scripts/per-once/boot.sh'.format(MNT_DIR), st.st_mode | stat.S_IEXEC)
        else:
            logging.warning("Skipping Cloud-Init Configuration")

        logging.info("c= Installing VMware Guest Agent (gugent) =======")
        if args.target != "openstack":
            if release in EPEL_OSS:
                ostype = 'rhel64'
            elif release in DEB_OSS:
                ostype = 'ubuntu64'
            call(['bash', '/tmp/vra.sh', '-n', '-l', ostype, '-j', 'true', '-m', args.vra_mgmt_server, '-M', args.vra_mgmt_port, '-a', args.vra_server, '-A', args.vra_port])
        else:
            logging.info("!! Skipping !!")

        logging.info("c= Enabling Services ============================")
        if release in EPEL_OSS:
            if os.path.exists("/usr/bin/systemctl"):
                call(["/usr/bin/systemctl", "enable", "NetworkManager"])
            else:
                call(["/sbin/chkconfig", "NetworkManager", "on"])
        elif release in SUSE_OSS:
            if os.path.exists("/usr/bin/systemctl"):
                call(["/usr/bin/systemctl", "enable", "cloud-init"])
        elif release in DEB_OSS:
            print()

        logging.info("c= Cleaning up Packages =========================")
        if release in EPEL_OSS:
            call(["/usr/bin/yum", "clean", "all"])

        logging.info("c= Preping Image (vRA) ==========================")
        if args.target == "vra":
            logging.info("Rebuilding CA Store...")
            call(CACommand)

    logging.info("== Unmounting ===================================")
    call(["umount", MNT_DIR])

    logging.info("== Cleaning Filesystem ==========================")
    logging.debug("Trying fsck")
    fsckr = call(["fsck", partition])
    if fsckr is not 0:
        logging.warning("fsck failed. Assuming invalid FileSystem")
        logging.debug("Trying xfs_repair")
        xfsr = call(["xfs_repair", partition])

    logging.info("== Disconnecting ================================")
    # call(["qemu-nbd", "--disconnect", NBDDevice])
    call(["umount", MNT_DIR])