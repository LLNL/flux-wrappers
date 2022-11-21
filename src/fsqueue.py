#!/bin/env python3
###############################################################
# Copyright 2020 Lawrence Livermore National Security, LLC
# (c.f. NOTICE.LLNS)
#
# SPDX-License-Identifier: LGPL-3.0
###############################################################

import argparse
import flux
import flux.job
import flux.hostlist
import re
import sys


class CustomHelpFormatter(argparse.HelpFormatter):
    """
    Create minimal argparse format to mimic that of Slurm.

    See https://stackoverflow.com/a/31124505 for original answer to shortening
    argparse's usage documentation.
    """

    def __init__(self, prog):
        super().__init__(prog, max_help_position=40, width=80)

    def _format_action_invocation(self, action):
        if not action.option_strings or action.nargs == 0:
            return super()._format_action_invocation(action)
        default = self._get_default_metavar_for_optional(action)
        args_string = self._format_args(action, default)
        return ", ".join(action.option_strings) + " " + args_string


def print_argwarn(argval):
    """
    print a warning for unsupported arguments
    """
    print(f'WARNING: "{argval}" is not supported by this wrapper and is being ignored.')
    print('WARNING: fsqueue is a wrapper script for the native "flux jobs" command.')
    print(
        'See "flux help jobs" or contact the LC Hotline for help using the native commands.'
    )
    return None


def parse_time(time):
    """
    turn a bunch of seconds into something human readable
    """
    itime = int(time)
    seconds = itime % 60
    mtime = int(itime / 60)
    minutes = mtime % 60
    htime = int(mtime / 60)
    if htime > 0:
        return f"{htime}:{minutes:02}:{seconds:02}"
    else:
        return f"{minutes:02}:{seconds:02}"


def get_queuestring(sched):
    """
    parse sched from flux to get queue
    """
    return f"{sched.queue}"


def sprintf(format_string, types_dict):
    """
    print output to minimc slurm's format language
    """
    result = []
    prev_end = 0
    for token in re.finditer(r"%\.?[0-9]*[^%\s]?", format_string):
        result.append(format_string[prev_end:token.start()])

        width_match = re.match(r"\.*[0-9]+", token.group()[1:])
        if width_match is not None:
            width_string = width_match.group()
            output = types_dict[token.group().replace(width_string, "")]
            if width_string[0] == '.':
                width = int(width_string[1:])
                output = f"{output:>{width}}"[:width]
            else:
                width = int(width_string)
                output = f"{output:<{width}}"[:width]
        else:
            output = types_dict[token.group()]

        result.append(output)

        prev_end = token.end()

    result.append(format_string[prev_end:])
    print("".join(result))


def printsqueueheader(format_string):
    """
    print header for output
    """
    types = {
        "%a": "USERNAME",
        "%i": "JOBID",
        "%P": "PARTITION",
        "%j": "NAME",
        "%u": "USER",
        "%t": "STATUS",
        "%M": "TIME",
        "%D": "NODES",
        "%R": "NODELIST(REASON)"
    }

    sprintf(format_string, types)


def printsqueue(j, format_string):
    """
    print one job
    """
    remstring = parse_time(j.t_remaining)
    reasonnode = j.sched.reason_pending
    if f"{j.sched.reason_pending}" == "":
        reasonnode = j.nodelist
    partition = get_queuestring(j.sched)

    types = {
        "%a": j.username,
        "%i": j.id.f58,
        "%P": partition,
        "%j": j.name,
        "%u": j.username,
        "%t": j.status_abbrev,
        "%M": remstring,
        "%D": j.nnodes,
        "%R": reasonnode
    }

    sprintf(format_string, types)


def main(parsedargs):
    args, unknown_args = parsedargs
    if unknown_args:
        print_argwarn(" ".join(unknown_args))

    # -------------------------------------------------------------------------
    # Configure user for command scope
    # -------------------------------------------------------------------------
    # Set user if explicitly specified.
    user = "all"
    if args.user is not None:
        user = args.user

    # -------------------------------------------------------------------------
    # Configure explicit job_states if given.
    # -------------------------------------------------------------------------
    # Set default job_states for search.
    job_states = ["pending", "running"]

    # Validate given job state.
    if args.state is not None:
        # Load dictionary of known states and their aliases.
        known_states = {
            "running": "running",
            "r": "running",
            "pending": "pending",
            "pd": "pending",
            "all": "active",
        }
        if args.state.lower() in known_states.keys():
            job_states = [known_states[args.state.lower()]]
        else:
            print(f"Invalid job state specified: {args.state}", file=sys.stderr)
            print(f"Valid job states include: {','.join(known_states.keys())}")
            exit(1)

    # -------------------------------------------------------------------------
    # Configure explicit job_id if given.
    # -------------------------------------------------------------------------
    # Set default job_ids as an empty list in the case a job_id is not explicitly
    # extered as an argument.
    job_ids = []

    # Build job_id if given as an explicit argument.
    if args.jobs is not None:
        for id in args.jobs.split(","):
            job_ids.append(flux.job.JobID(id))

    # Initialize connection to flux.
    conn = flux.Flux()

    # -------------------------------------------------------------------------
    # Query Flux for JobList
    # -------------------------------------------------------------------------
    # Retrieve jobs and attributes from flux.
    rpc = flux.job.JobList(
        conn, user=user, ids=job_ids, filters=job_states
    ).fetch_jobs()
    jobs = list(rpc.get_jobinfos())

    # -------------------------------------------------------------------------
    # Filter retrived jobs based on job properies and given arguments.
    # -------------------------------------------------------------------------
    # Filter so that all jobs are running on a node in args.nodelist if provided.
    if args.nodelist is not None:
        nodelist = [node.strip() for node in args.nodelist.split(",")]
        jobs = [job for job in jobs if job.nodelist in nodelist]

    if args.noheader is False:
        printsqueueheader(args.format)

    for job in jobs:
        printsqueue(job, args.format)


if __name__ == "__main__":
    def fmt(prog): return CustomHelpFormatter(prog)
    parser = argparse.ArgumentParser(
        description="List running and queued jobs in squeue format.",
        conflict_handler="resolve",
        allow_abbrev=False,
        formatter_class=fmt,
    )

    parser.add_argument("-u", "--user", metavar="<user>", help="show jobs run by user")
    parser.add_argument(
        "-t",
        "--state",
        metavar="<state>",
        help='use "-t all" to show jobs in all states, including completed jobs',
    )
    parser.add_argument(
        "-j",
        "--jobs",
        metavar="<jobid>,<jobid>,....",
        help="display only jobs specified",
    )
    parser.add_argument(
        "-h", "--noheader", action="store_true", help="do not print a header"
    )
    parser.add_argument(
        "-o",
        "--format",
        metavar="<format>",
        default="%.18i %.9P %.8j %.8u %.2t %.10M %.6D %R",
        help="format specification"
    )

    parser.add_argument(
        "-w", "--nodelist", metavar="<nodelist>", help="show jobs that ran on nodelist"
    )

    main(parser.parse_known_args())
