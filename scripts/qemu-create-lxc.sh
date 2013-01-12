QEMU_PATH=$(dirname $(dirname $(readlink -f $0)))

TARGET_LIST="i386 m68k alpha sparc mips ppc raspberrypi"

set_i386() {
	: nothing specific
}

set_m68k() {
	DEBIAN_REPO=http://archive.debian.org/debian
	DEBIAN_DIST=etch-m68k
	DEBIAN_SIGN=55BE302B

        CONFIGURE_PARAMS=--m68k-default-cpu=m68040
}

set_alpha() {
	DEBIAN_REPO=http://archive.debian.org/debian
	DEBIAN_DIST=lenny
}

set_sparc() {
	QEMU_TARGET=sparc32plus
}

set_mips() {
	: nothing specific
}

set_ppc() {
	DEBIAN_TARGET=powerpc
}

set_raspberrypi() {
	DEBIAN_REPO=http://archive.raspbian.org/raspbian
	DEBIAN_DIST=wheezy
	DEBIAN_SIGN=""
	DEBIAN_TARGET=armhf
	QEMU_TARGET=arm
}

check_target() {
	found=0
	for available in $TARGET_LIST
	do
		if [ "$available" = "$TARGET" ]
		then 
			found=1
			break;
		fi
	done
	if [ $found -eq 0 ]
	then
		echo "ERROR: unknown target $TARGET" 1>&2
		exit 1
	fi

	# generic values

	CONTAINER_NAME=virt${TARGET}
	CONTAINER_PATH=/containers/${TARGET}
	LXC_CONF=$HOME/lxc-${TARGET}.conf

	DEBIAN_REPO=http://ftp.debian.org/debian
	DEBIAN_DIST=stable
	DEBIAN_SIGN=""
	DEBIAN_TARGET=$TARGET

	QEMU_TARGET=$TARGET

	CHECK_BIN=check_default

	# target specific values

	set_$TARGET

	QEMU_BIN=${QEMU_PATH}/build-${QEMU_TARGET}/${QEMU_TARGET}-linux-user/qemu-${QEMU_TARGET}
}

check_m68k() {
	if ${QEMU_BIN} -cpu help | grep -q ">m68040"
	then
		echo "Found an existing qemu-m68k, use it !" 1>&2
		return 0
	fi
	echo "Found an existing qemu-m68k, but with no m68040 emulation" 1>&2
	echo "Please, remove it" 1>&2
	echo "m68040 emulation is available from " 1>&2
	echo "git clone git://gitorious.org/qemu-m68k/qemu-m68k.git"
	exit 1
}

check_default() {
	test -e ${QEMU_BIN}
}

installed_dpkg() {
	dpkg --status "$1" > /dev/null 2>&1
}

check_env() {
	if [ ! -e /etc/debian_version ]
	then
		echo "ERROR: this script works only on Debian based distro" 1>&2
		exit 1
	fi
	for pkg in zlib1g gcc make debootstrap lxc
	do
		if  ! installed_dpkg $pkg
		then
			echo "ERROR: $pkg is needed" 1>&2
			exit 1
		fi
	done
}

create_qemu() {
	if [ -e "${QEMU_BIN}" ]
	then
		if ${CHECK_BIN}
		then
			return 0
		fi
	fi
	echo "cd ${QEMU_PATH} && \
	mkdir build-${QEMU_TARGET} && \
	cd build-${QEMU_TARGET} && \
	../configure --static --suid-able ${CONFIGURE_PARAMS} \
		     --target-list=${QEMU_TARGET}-linux-user && \
	make" | sudo -i -u ${SUDO_USER}
	if ! ${CHECK_BIN}
	then
		echo "ERROR: generated qemu binary is invalid !" 1>&2
		exit 1
	fi
}

create_root() {
	# sanity check

	if [ $(readlink -f ${CONTAINER_PATH}/) = "/" ]
	then
		echo "ERROR: invalid path ${CONTAINER_PATH}" 1>&2
		exit 1
	fi

	# check directory

	if [ -e "${CONTAINER_PATH}" ]
	then
		echo "${CONTAINER_PATH} already exists" 1>&2
		echo "Please, remove it" 1>&2
		exit 1
	fi

	# Debian bootstrap

	mkdir -p "${CONTAINER_PATH}"
	debootstrap --foreign \
		    --arch=${DEBIAN_TARGET} \
                    ${DEBIAN_DIST} ${CONTAINER_PATH} \
		    ${DEBIAN_REPO} && \

	# adding qemu binary

	cp ${QEMU_BIN} ${CONTAINER_PATH}/bin && \
	chown root:root ${CONTAINER_PATH}/bin/qemu-${QEMU_TARGET} && \
	chmod +s ${CONTAINER_PATH}/bin/qemu-${QEMU_TARGET} && \
	${QEMU_PATH}/scripts/qemu-update-binfmt ${QEMU_TARGET}

	# debian bootstrap second stage

	chroot ${CONTAINER_PATH} debootstrap/debootstrap --second-stage

	# configuration

	cat >> ${CONTAINER_PATH}/etc/fstab <<!EOF
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc		/proc		proc	nodev,noexec,nosuid 0	1
devpts		/dev/pts	devpts	nodev,noexec,nosuid 0	1
!EOF

	echo "$CONTAINER_NAME" > ${CONTAINER_PATH}/etc/hostname
	echo "c:2345:respawn:/sbin/getty 38400 console" >> ${CONTAINER_PATH}/etc/inittab

	cat >> ${CONTAINER_PATH}/etc/network/interfaces <<!EOF
auto eth0
iface eth0 inet dhcp
!EOF

	cat >> ${CONTAINER_PATH}/etc/apt/sources.list <<!EOF
deb ${DEBIAN_REPO} ${DEBIAN_DIST} main contrib non-free
deb-src ${DEBIAN_REPO} ${DEBIAN_DIST} main contrib non-free
!EOF

	rm -f ${CONTAINER_PATH}/dev/ptmx

	if [ "$DEBIAN_SIGN" != "" ]
	then
		HOME=/root chroot ${CONTAINER_PATH} gpg --keyserver pgpkeys.mit.edu --recv-key ${DEBIAN_SIGN}
		HOME=/root chroot ${CONTAINER_PATH} gpg -a --export ${DEBIAN_SIGN} | chroot ${CONTAINER_PATH}  apt-key add -
	fi
	chroot ${CONTAINER_PATH} apt-get update
	chroot ${CONTAINER_PATH} dpkg-reconfigure tzdata
	chroot ${CONTAINER_PATH} apt-get install locales
	chroot ${CONTAINER_PATH} dpkg-reconfigure locales
	chroot ${CONTAINER_PATH} passwd
}

create_lxc() {
	cat > ${LXC_CONF} <<!EOF
lxc.utsname = ${CONTAINER_NAME}

lxc.network.type = veth
lxc.network.flags = up
lxc.network.link = lxcbr0
lxc.network.name = eth0

lxc.pts=1023
lxc.tty=12

lxc.rootfs = ${CONTAINER_PATH}

lxc.cgroup.devices.deny = a
lxc.cgroup.devices.allow = c 136:* rwm # pts
lxc.cgroup.devices.allow = c 254:0 rwm # rtc
lxc.cgroup.devices.allow = c 5:* rwm 
lxc.cgroup.devices.allow = c 4:* rwm # ttyXX
lxc.cgroup.devices.allow = c 1:* rwm
lxc.cgroup.devices.allow = b 7:* rwm # loop
lxc.cgroup.devices.allow = b 1:* rwm # ram

!EOF
	lxc-create -n ${CONTAINER_NAME} -f ${LXC_CONF}
}

TARGET="$1"

if [ "$TARGET" = "" ]
then
	echo "ERROR: you must provide a target." 1>&2
	echo "       Available targets are:" 1>&2
	echo "       $TARGET_LIST"
	exit 1
fi


check_env
check_target

echo "DEBIAN_TARGET : ${DEBIAN_TARGET}"
echo "QEMU_TARGET   : ${QEMU_TARGET}"
echo "CONTAINER_NAME: ${CONTAINER_NAME}"
echo "CONTAINER_PATH: ${CONTAINER_PATH}"
echo "QEMU_PATH     : ${QEMU_PATH}"
echo "LXC_CONF      : ${LXC_CONF}"
echo "DEBIAN_REPO   : ${DEBIAN_REPO}"
echo "DEBIAN_DIST   : ${DEBIAN_DIST}"

if lxc-list | grep -q ${CONTAINER_NAME}
then
	echo "${CONTAINER_NAME} already exists !" 1>&2
	echo "you can remove it with :" 1>&2
	echo "    sudo lxc-destroy -n ${CONTAINER_NAME}" 1>&2
	echo "[WARNING: this will remove the directory too]" 1>&2
	exit 2
fi

if [ "$USER" != "root" ]
then
	echo "You need to be root to run this command" 2>&1
	exit 3
fi

create_qemu
create_root
create_lxc

chroot ${CONTAINER_PATH} uname -a

echo "you can now start your container using:"
echo "    sudo lxc-start -n ${CONTAINER_NAME}"
