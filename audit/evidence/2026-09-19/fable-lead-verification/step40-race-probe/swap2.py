import os,sys,time
w=sys.argv[1]; sub=os.path.join(w,"scope","sub"); real=os.path.join(w,"scope","real"); out=os.path.join(w,"outside")
end=time.time()+float(sys.argv[2]); n=0
while time.time()<end:
    os.rename(sub,real); os.symlink(out,sub)
    os.unlink(sub); os.rename(real,sub)
    n+=1
print("swaps",n)
