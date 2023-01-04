#!/bin/env -S flux python
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
import sys
import os


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


def main(args):
    """Handle the main command logic of scancel."""
    myname = os.path.basename(__file__)

    # Don't print the wrapper announcement if the user requests quiet execution.
    if not args.quiet:
        print(
            f'WARNING: {myname} is a wrapper script for the native "flux job cancel" command.',
            file=sys.stderr,
        )

    # If no job_id nor any filter options are given we should print an error
    # to stderr and exit with a return node of 1 to mimic the behavior of
    # scancel.
    if len(args.job_id) < 1 and not len(sys.argv) > 1:
        print(f"{myname}: error: No job identification provided", file=sys.stderr)
        exit(1)

    # Print version information and exit if requested.
    if args.version:
        print("flux-wrappers 0.0.0")
        exit(0)

    # Set default signal code.
    signal = 9

    # Validate signal if given.
    if args.signal is not None:
        known_signals = {
            "SIGHUP": 1,
            "SIGINT": 2,
            "SIGQUIT": 3,
            "SIGABRT": 6,
            "SIGKILL": 9,
            "SIGALRM": 14,
            "SIGTERM": 15,
        }
        # Validate signal from argument.
        if isinstance(args.signal, int):
            signal = int(args.signal)
        elif args.signal.upper() in known_signals:
            signal = known_signals[args.signal.upper()]
        else:
            print(f"Unknown job signal: {args.signal}", file=sys.stderr)
            exit(1)

    # Initialize connection to flux.
    conn = flux.Flux()

    # -------------------------------------------------------------------------
    # Configure explicit job_id if given.
    # -------------------------------------------------------------------------
    # Set default job_ids as an empty list in the case a job_id is not explicitly
    # extered as an argument.
    job_ids = []

    # Set default job_filters as an dictionary list that will be appended to
    # based on the presence of different filters.
    job_filters = {}

    # Build job_id if given as an explicit argument.
    for id in args.job_id:
        job_ids.append(flux.job.JobID(id))

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
        }
        if args.state.lower() in known_states.keys():
            job_states = [known_states[args.state.lower()]]
            job_filters["state"] = ",".join(job_states)
        else:
            print(f"Invalid job state specified: {args.state}", file=sys.stderr)
            print("Valid job states are PENDING and RUNNING")
            exit(1)

    # -------------------------------------------------------------------------
    # Configure user for command scope
    # -------------------------------------------------------------------------
    # By default set the user based on the user executing the command.
    user = os.getlogin()

    # Overwrite default user if explicitly specified.
    if args.user is not None:
        user = args.user

    # Translate root to 'all' scope for flux compatibility.
    if user == "root":
        user = "all"

    # Add user to filters for verbose output.
    job_filters["user"] = user

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
        nodelist = flux.hostlist.Hostlist(args.nodelist)
        jobs = [job for job in jobs if job.nodelist in nodelist]
        job_filters["nodelist"] = ",".join(nodelist)

    # Filter so that all jobs have the name args.name if provided.
    if args.name is not None:
        jobs = [job for job in jobs if job.name == args.name]
        job_filters["name"] = args.name

    # Filter so that all jobs are within the partition args.partition if provided.
    if args.partition is not None:
        jobs = [job for job in jobs if job.sched.queue == args.partition]
        job_filters["partition"] = args.partition

    # Catch the case where no jobs made it through the filters and tell the
    # user on verbose output.
    if args.verbose and len(jobs) < 1:
        print(
            f"{myname}: error: No active jobs match ALL job filters, including:",
            end=" ",
            file=sys.stderr,
        )
        print(
            ",".join(
                [f"{filter}={job_filters[filter]}" for filter in job_filters.keys()]
            ),
            file=sys.stderr,
        )

    # -------------------------------------------------------------------------
    # Cancel filtered jobs.
    # -------------------------------------------------------------------------
    for job in jobs:
        # If interactive prompt for confirmation before cancelling any jobs.
        if args.interactive:
            answer = ""
            while answer not in ["y", "n"]:
                print(
                    f"Cancel job_id={job.id.f58} name={job.name} partition={job.sched.queue} [y/n]?",
                    end=" ",
                )
                answer = input().lower()
            if answer == "n":
                continue

        try:
            # Send signal if args.signal is present, else default to cancel.
            if args.signal is not None:
                # Send signal to flux job.
                flux.job.kill(conn, job.id, signum=signal)
            else:
                # Cancel a running job in flux.
                flux.job.cancel(conn, job.id)

        # Print error to user if they don't have permission to cancel a job.
        except PermissionError:
            print(
                f"{myname}: error: Kill job error on job id {job.id}: Access/permission denied",
                file=sys.stderr,
            )
        except FileNotFoundError:
            if args.verbose:
                print(
                    f"{myname}: error: Kill job error on job id {job.id}: Invalid job id specified",
                    file=sys.stderr,
                )


if __name__ == "__main__":
    fmt = lambda prog: CustomHelpFormatter(prog)
    parser = argparse.ArgumentParser(
        description="scancel like wrapper for Flux.", formatter_class=fmt
    )

    # parser.add_argument(
    #    "-A",
    #    "--account",
    #    metavar="<account>",
    #    help="act only on jobs charging this account",
    # )
    # parser.add_argument(
    #    "-b",
    #    "--batch",
    #    action="store_true",
    #    help="signal batch shell for specified job",
    # )
    # parser.add_argument(
    #    "-f",
    #    "--full",
    #    action="store_true",
    #    help="signal batch shell and all steps for specified job",
    # )
    parser.add_argument(
        "-i",
        "--interactive",
        action="store_true",
        help="require response from user for each job",
    )
    parser.add_argument(
        "-n", "--name", metavar="<job_name>", help="act only on jobs with this name"
    )
    parser.add_argument(
        "-p",
        "--partition",
        metavar="<partition>",
        help="act only on jobs in this partition",
    )
    parser.add_argument("-Q", "--quiet", action="store_true", help="disable warnings")
    # parser.add_argument(
    #    "-q",
    #    "--qos",
    #    metavar="<qos>",
    #    help="act only on jobs with this quality of service",
    # )
    # parser.add_argument(
    #    "-R",
    #    "--reservation",
    #    metavar="<reservation>",
    #    help="act only on jobs with this reservation",
    # )
    parser.add_argument(
        "-s",
        "--signal",
        metavar="<name>|<integer>",
        nargs="?",
        const=9,
        help="signal to send to job, default is SIGKILL",
    )
    parser.add_argument(
        "-t", "--state", metavar="<state>", help="act only on jobs in this state"
    )
    parser.add_argument(
        "-u",
        "--user",
        metavar="<username>",
        help="act only on jobs of this user",
    )
    parser.add_argument(
        "-V",
        "--version",
        action="store_true",
        help="output version information and exit",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="show verbose output"
    )
    parser.add_argument(
        "-w",
        "--nodelist",
        metavar="<node_list>",
        help="act only on jobs on these nodes",
    )

    # Add positional arguments.
    parser.add_argument("job_id", metavar="job_id", nargs="*")

    # Parse arguments and begin execution.
    args = parser.parse_args()
    main(args)
