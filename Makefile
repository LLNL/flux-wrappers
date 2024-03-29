# basic Makefile to set up links without filename extensions and such
SHELL = /bin/sh
VPATH = src
commands = srun salloc sbatch squeue showq sinfo slurm2flux

all : $(commands)
.PHONY : install

showq : fshowq.py 
	ln -is $< showq
squeue : fsqueue.py 
	ln -is $< squeue
sinfo : sinfo.pl
	ln -is $< sinfo
srun salloc sbatch slurm2flux : slurm2flux.pl
	ln -is $< $@

.PHONY : clean
clean :
	-rm -f $(commands)
