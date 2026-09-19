from pathlib import Path
import subprocess,json,tarfile,io,hashlib
run=lambda args:subprocess.run(args,check=True,text=True,capture_output=True,timeout=40)
print(run(["systemctl","stop","docker.socket","docker.service"]).stdout)
Path("/etc/docker").mkdir(exist_ok=True)
config={"bridge":"none","iptables":False,"ip6tables":False,"ip-forward":False,"ip-masq":False,"exec-opts":["native.cgroupdriver=systemd"],"cgroup-parent":"mo-executor.slice","log-driver":"none","live-restore":False}
Path("/etc/docker/daemon.json").write_text(json.dumps(config,indent=2)+"\n")
Path("/etc/systemd/system/mo-executor.slice").write_text("[Unit]\nDescription=Bounded Mo candidate containers\n[Slice]\nCPUQuota=100%\nMemoryMax=512M\nMemorySwapMax=0\nTasksMax=128\n")
run(["systemctl","daemon-reload"])
run(["systemctl","start","mo-executor.slice","docker.service"])
busybox=Path("/usr/bin/busybox")
rootfs=Path("/tmp/mo-executor-fixture.tar")
with tarfile.open(rootfs,"w") as tar:
 for name in ["bin","work","tmp","reference"]:
  info=tarfile.TarInfo(name);info.type=tarfile.DIRTYPE;info.mode=0o755;tar.addfile(info)
 tar.add(busybox,arcname="bin/busybox")
 info=tarfile.TarInfo("bin/sh");info.type=tarfile.SYMTYPE;info.linkname="busybox";info.mode=0o755;tar.addfile(info)
print("busybox_sha256="+hashlib.sha256(busybox.read_bytes()).hexdigest())
print(run(["docker","import",str(rootfs),"mo-executor-fixture:r01"]).stdout)
rootfs.unlink()
for args in [["docker","version","--format","{{.Server.Version}}"],["docker","info","--format","{{.CgroupDriver}} {{.CgroupVersion}} {{json .SecurityOptions}}"],["docker","image","inspect","mo-executor-fixture:r01","--format","{{.Id}}"],["systemctl","show","mo-executor.slice","--property=CPUQuotaPerSecUSec,MemoryMax,MemorySwapMax,TasksMax"],["dpkg-query","-W","docker.io","busybox-static","containerd","runc"]]:
 print("command:",args);print(run(args).stdout)
