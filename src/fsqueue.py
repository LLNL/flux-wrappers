#!/bin/env python3
###############################################################
# Copyright 2020 Lawrence Livermore National Security, LLC
# (c.f. NOTICE.LLNS)
#
# SPDX-License-Identifier: LGPL-3.0
###############################################################

import argparse
import flux
import flux.job as fjob
from flux.hostlist import Hostlist

def print_argwarn(argval) :
	'''
	print a warning for unsupported arguments
	'''
	print(f'WARNING: "{argval}" is not supported by this wrapper and is being ignored.')
	print('WARNING: fsqueue is a wrapper script for the native "flux jobs" command.')
	print('See "flux help jobs" or contact the LC Hotline for help using the native commands.') 
	return None

def parse_time(time) :
	'''
	turn a bunch of seconds into something human readable
	'''
	itime = int(time)
	seconds = itime % 60
	mtime = int( itime / 60 )
	minutes = mtime % 60
	htime = int( mtime / 60 )
	if htime > 0 :
		return f"{htime}:{minutes:02}:{seconds:02}"
	else :
		return f"{minutes:02}:{seconds:02}"

def filter_byhostlist(j, jobfilter) :
    '''
    filter out jobs that did not run on hosts in jobfilter
    '''
    filtered_jobs = []
    for job in j.jobs() :
        for host in Hostlist(jobfilter) :
            if host in Hostlist(job.nodelist) :
                filtered_jobs.append(job)
    return filtered_jobs

def get_queuestring(sched) :
	'''
	parse sched from flux to get queue
	'''
	return f"{sched.queue}"

def printsqueueheader() :
	'''
	print header for output
	'''
	print("               JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)")

def printsqueue(j, alljobs=False) :
	'''
	print one job
	'''
	jobdone = False
	if j.status_abbrev == "CD" or \
	   j.status_abbrev == "CA" or \
	   j.status_abbrev == "TO" or \
	   j.status_abbrev == "F" :
		jobdone = True
	if alljobs == True or jobdone == False :
		remstring = parse_time(j.t_remaining)
		reasonnode = j.sched.reason_pending
		if f"{j.sched.reason_pending}" == "" :
			reasonnode=j.nodelist
		partition = get_queuestring(j.sched)
		print(f"         {j.id.f58:>10} {partition:>9} {j.name:>8.8} {j.username:>8} {j.status_abbrev:>2} {remstring:>10} {j.nnodes:>6} {reasonnode}")
#		print(f"         {j.id} partition {j.name} {j.username} {j.status_abbrev} {j.t_remaining} {j.nnodes} {j.sched.reason_pending}")

def main(parsedargs) :
    args, unknown_args = parsedargs
    if unknown_args  :
        print_argwarn(" ".join(unknown_args))
    if args.user != None :
        user = args.user
    else :
        user = "all"
    if args.state != None :
        printall=True
        if args.state != "all" :
            print_argwarn(f"-t {args.state}")
    else :
        printall=False
    myhandle = flux.Flux()
    if args.jobs == None :
        mylist = fjob.JobList(myhandle,user=user)
    else :
        jobidlist = []
        for j in args.jobs.split(",") :
            jobidlist.append(fjob.id_parse(j))
        mylist = fjob.JobList(myhandle,user=user,ids=jobidlist)
    if args.nodelist:
        myjoblist = filter_byhostlist(mylist, args.nodelist)
    else :
        myjoblist = mylist.jobs()
    if args.noheader != True :
        printsqueueheader()
    for job in myjoblist :
        printsqueue(job, alljobs=printall)

if __name__ == '__main__' :
    parser = argparse.ArgumentParser(description="List running and queued jobs in squeue format.", conflict_handler='resolve', allow_abbrev=False)
    parser.add_argument('-u', '--user', metavar='<user>', help='show jobs run by user')
    parser.add_argument('-t', '--state', metavar='<state>', help='use "-t all" to show jobs in all states, including completed jobs')
    parser.add_argument('-j', '--jobs', metavar='<jobid>,<jobid>,....', help='display only jobs specified')
    parser.add_argument('-h', '--noheader', action='store_true', help='do not print a header')
    parser.add_argument('-w', '--nodelist', metavar='<nodelist>', help='show jobs that ran on nodelist')
    main(parser.parse_known_args())
