# escimg - anh Docker toi gian dung boi sinh vien de tao container moi qua
# docker.sock bi lo (Nhiem vu 2). Duoc "docker build" CUC BO tren host-sim, ngay sau
# khi dockerd khoi dong (xem host-sim/_bin/fixlocal.sh) - KHONG can Internet, KHONG
# can pull tu Docker Hub luc runtime (dung dung yeu cau lab chay offline).
#
# busybox (build tinh, khong phu thuoc thu vien ngoai, lay tu goi apt busybox-static
# luc build image host-sim) duoc COPY nhieu lan sang cac ten khac nhau vi FROM scratch
# khong co shell nen khong the tao symlink bang RUN; moi COPY nhung the tinh
# argv[0]/ten file de chon dung applet (sh, chroot, cat, ls, hostname, mount...).
FROM scratch
COPY busybox /bin/busybox
COPY busybox /bin/sh
COPY busybox /bin/chroot
COPY busybox /bin/cat
COPY busybox /bin/ls
COPY busybox /bin/hostname
COPY busybox /bin/mount
COPY busybox /bin/id
