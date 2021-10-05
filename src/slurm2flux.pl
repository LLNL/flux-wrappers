#! /usr/bin/perl

# Written by Philip D. Eckert <eckert2@llnl.gov> and Ryan Day <day36@llnl.gov>

use Getopt::Long 2.24 qw(:config no_ignore_case);
use strict;

	
#
# Define all possible Slurm options, whether Flux supports them or not.
#
my (
$account_opt, $acct_freq_opt, $ail_type_opt, $alps_opt, $attach_opt, $batch_opt, $beginbxopt, $blrts_imnage_opt, $chdir_opt, $checkpoint_opt, $checkpoint_dir_opt, $cnloab_image_opt, $comment_opt, $constraint_opt, $cores_per_socket_opt, $cpu_bind_opt, $cpus_per_task_opt, $debugger_test_opt, $debugger_test_opt, $dependent_opt, $disable_status_opt, $distribution_opt, $error_opt, $exclude_opt, $exclusive_opt, $flux_debug_opt, $geometry_opt, $get_user_env_opt, $gid_val, $gpus_per_node_opt, $gpus_per_task_opt, $gres_opt, $hint_opt, $hold_opt, $immediate_opt, $input_opt, $ioload_images_opt, $job_name_val, $jobid_opt, $join_opt, $kill_on_bad_exit_opt, $label_opt, $licenses_opt, $linux_image_opt, $mail_exit_opt, $mail_launch_time_opt, $mail_user_opt, $mem_bind_opt, $mem_opt, $mem_per_cpu_opt, $mincores_opt, $mincpus_opt, $minsockets_opt, $minthreads_opt, $mloaver_image_opt, $mpi_opt, $msg_timeout_opt, $multi_prog_opt, $network_opt, $nice_opt, $no_allocate_opt, $no_kill_opt, $no_rotate_opt, $nodelist_opt, $nodes_opt, $ntasks_opt, $ntasks_per_core_opt, $ntasks_per_node, $ntasks_per_socket_opt, $open_mode_opt, $outoput_opt, $output_opt, $overcommit_opt, $partition_opt, $preserve_opt, $priority_opt, $prolog_opt, $propagate_opt, $pty_opt, $qos_opt, $quiet_on_ibnterupt_opt, $quiet_opt, $ramdisk_image_opt, $reboot_opt, $relative_opt, $reservation_opt, $restarert_dir_opt, $resv_ports_opt, $share_opt, $signal_opt, $sockets_per_node_opt, $task_epilog_opt, $task_prolog_opt, $tasks_per_node_opt, $test_only_opt, $tghreads_per_core_opt, $threads_opt, $time_min_opt, $time_opt, $tmp_opt, $uid_opt, $unbuffered_opt, $usage_opt, $verbose_opt, $version_opt, $vextra_node_al, $wait_opt, $wckey_opt, $help_opt, $Z_opt
); 

my (@lreslist, @SlurmScriptOptions);
my ($commandLine, $scriptFile, $scriptArgs, $tempFile, $command, $flag);
my @OPTIONS = ();

#
# Save off ARGV so we can override the script directives if needed later (sbatch)
#
my @SAVEDARGV = @ARGV;

GetOpts(@ARGV);
usage() if ($help_opt);

#
# If we're running in batch mode (sbatch) we need to parse the script for #SBATCH stuff.
# Otherwise, we just can just pass the rest on to flux.
#
if( $0 =~ /sbatch$/ ){
    # At this point the only thing left on ARGV should be the script and
    # script arguments (if any).
    if (@ARGV) {
    	$scriptFile = shift;
        open FDIN, "< $scriptFile" or die "Unable to open $scriptFile for reading: $!\n";
		$scriptArgs = join ' ', @ARGV if @ARGV;
    }
    # Otherwise read the job command file from STDIN and create a temporary file using
    # the process id as part of the name (for uniqueness).
    else {
	    open FDIN, "< &STDIN";
    	$tempFile = "/tmp/jobScript.flux.$$";
    	open FDOUT, "> $tempFile"
	    	or die( "Unable to open temporary job script file ($tempFile) for writing: $!\n"
	    );
    }

    # Check job script
    my $lineCtr = 0;
    foreach my $line (<FDIN>) {
    	$lineCtr++;
    	if (($lineCtr == 1) && ($line !~ /^#!/ && $tempFile)) {
	        print FDOUT "#! /bin/sh\n";
    	}
    	print FDOUT $line if( $tempFile);
    	if ($line =~ /^\s*#\s*SBATCH\s+/) {
	        chomp $line;
	        $line =~ s/^\s*#\s*SBATCH\s+//; # Remove #SBATCH from line.
	        $line =~ s/#.*//;               # Remove comments
	        $line =~ s/\s+$//;              # Remove trailing whitespace
	        my @args = split /\s+/, $line;
	        foreach my $arg (@args) {
	                push @SlurmScriptOptions, @args;
	        }
	    }
    }
    close FDIN;
    close FDOUT;
    
    # Check script options.
    GetOpts(@SlurmScriptOptions) 
	    or die("Invalid SLURM options found in job script file.\n");
    # Check command line arguments (overriding script directives if any)
    GetOpts(@SAVEDARGV);
}else{
    $commandLine = "@ARGV";
}

#
# Translate options
#
if ($comment_opt) {
	push @OPTIONS, "--setattr=user.comment=$comment_opt ";
}

if ($cpus_per_task_opt) {
    push @OPTIONS, "-c $cpus_per_task_opt ";
}

if ($chdir_opt) {
    push @OPTIONS, "--setatttr=system.cwd=$chdir_opt ";
}

if ($error_opt) {
	push @OPTIONS, "-error=$error_opt ";
}

if ($flux_debug_opt) {
	push @OPTIONS, "--debug ";
}

if ($input_opt) {
    push @OPTIONS, "--input=$input_opt ";
}

if ($gpus_per_task_opt) {
    push @OPTIONS, "-g $gpus_per_task_opt ";
}

if ($help_opt) {
	usage();
}

if ($label_opt) {
    push @OPTIONS, "--label-io ";
}

if ($ntasks_opt) {
	push @OPTIONS, "-n $ntasks_opt ";
}

if ($nodes_opt) {
	push @OPTIONS, "-N $nodes_opt ";
}

if ($output_opt) {
	push @OPTIONS, "--output=$output_opt ";
}

if ($partition_opt) {
    push @OPTIONS, "--setattr=system.queue=$partition_opt ";
}

if ($priority_opt) {
	push @OPTIONS, "--urgency=$priority_opt ";
}

if ($time_opt) {
	my $time = timeToSeconds($time_opt);
	push @OPTIONS, "-t $time ";
}

if ($hold_opt) {
    push @OPTIONS, "--urgency=0 ";
}

if ($verbose_opt) {
	push @OPTIONS, "-v ";
}

if ($Z_opt) {
	push @OPTIONS, "--dry-run ";
}

#
# decide what flux command to run based on the Slurm command and run it
#
if( $0 =~ /srun$/ ){
    if( $verbose_opt ) {
        print "# running: flux mini run @OPTIONS $commandLine\n";
    }
	system("flux mini run @OPTIONS $commandLine");
}elsif( $0 =~ /sbatch$/ ){
	if ($scriptFile || $tempFile) {
	    if ($scriptFile) {
	    	$command = $scriptFile;
	    } else {
    		$command = $tempFile;
    	}
    	$command .= " $scriptArgs" if ($scriptArgs);
    }
    if( $verbose_opt ) {
        print "# running: flux mini submit @OPTIONS $command\n";
    }
	system("flux mini submit @OPTIONS $command");
}elsif( $0 =~ /salloc$/ ){
    if( $verbose_opt ) {
        print "# running: flux mini alloc @OPTIONS $commandLine\n";
    }
	system("flux mini alloc @OPTIONS $commandLine");
}else{
    printf("flux mini COMMAND @OPTIONS $command\n");
}

exit;

#
# translate Slurm time format (days-hours:minutes:seconds) to seconds
#
sub timeToSeconds
{
	my ($duration) = @_;
	$duration = 0 unless $duration;
	my $seconds = 0;

	$duration = "366:00:00:00" if ($duration =~ /UNLIMITED/);

	my @req = split /:|-/, $duration;
	if ($duration =~ /^(\d+)$/) {
	        $seconds = $duration;
	} else {
	        my $inc;
	        $seconds = pop(@req);
	        $seconds += (60 * $inc) if ($inc = pop(@req));
	        $seconds += (60*60 * $inc) if ($inc = pop(@req));
	        $seconds += (24*60*60 * $inc) if ($inc = pop(@req));
	}

    # Time must be at least 1 minute (60 seconds)
	$seconds = 60 if $seconds < 60;
	$seconds .= "s";

	return $seconds;
}


#
# Check the option, need at least a job id.
#
sub GetOpts
{
	@ARGV = @_;

#
#       A little hacking with the ARGV array to allows
#       arguments and parameters to be squeezed together
#       like msub allows. This works becuase msub paired
#       arguments options, are only one character.
#
#       ie. -A abc  can be -Aabc
#
	my @NARGV;
	foreach my $tmp (@ARGV) {
		chomp $tmp;
	        $tmp =~ s/^--/-/;
	        if ($tmp =~ /^-/ && $tmp !~ /=/) {
	                if (length($tmp) > 2   &&
	                     $tmp !~ /man/     &&
	                     $tmp !~ /version/ &&
	                     $tmp !~ /slurm/   &&
	                     $tmp !~ /help/) {
	                        my ($arg1) = ($tmp =~ m/^(..)/);
	                        my ($arg2) = ($tmp =~ m/^..(.*)/);
	                        push @NARGV, $arg1;
	                        push @NARGV, $arg2;
	                } else {
	                        push @NARGV, $tmp;
	                }
	        } else {
	                push @NARGV, $tmp;
	        }
	}

	@ARGV = @NARGV;

	return GetOptions(
		'c|cpus-per-task=s' 	=> \$cpus_per_task_opt,
		'comment=s'          	=> \$comment_opt,
        'D|chdir=s'           => \$chdir_opt,
		'e|error=s'         	=> \$error_opt,
        'gpus-per-task=s'   => \$gpus_per_task_opt,
        'H|hold'            => \$hold_opt,
		'h|help'         	=> \$help_opt,
        'i|input=s'             => \$input_opt,
        'l|label'         		=> \$label_opt,
		'N|nodes=s'         	=> \$nodes_opt,
		'n|ntasks=s'        	=> \$ntasks_opt,
		'nice=s'         	=> \$priority_opt,
		'o|output=s'        	=> \$output_opt,
        'p|partition=s'     		=> \$partition_opt,
		'slurmd-debug=s'     	=> \$flux_debug_opt,
		't|time=s'          	=> \$time_opt,
		'v|verbose'       	=> \$verbose_opt,
		'Z|no-allocate'   	=> \$no_allocate_opt,
	);
}


#
# Usage.
#
sub usage
{

	printf("
    -Slurm compatible options supported in Flux-

OPTIONS
=======
-c|cpus-per-task=<count>    Number of cpus per task.
--comment=<comment>         User defined comment.
-D|--chdir=<directory>      Specify a working directory.
-e|--error=<filename>       Path and file name for stderr data.
--gpus-per-task=<count>     Number of gpus per task.
-H|--hold                   Submit job in a 'held' state.
-h|--help                   List the available options.
-i|--input=<filename>       Path and file name for stdin.
-l|--label                  Label IO with task tank prefixes.
-N|--nodes=<count>          Number of nodes needed.
-n|--ntasks=<count>         Number of tasks needed.
--nice=<number>             User defined priority.
-o|--output=<filename>      Path and file name for stdout data.
-p|--partion=<partition>    Partition or queue to submit job to.
--slurmd-debug=<level>      Debugging added.
-t|--time=<timelimit>       Wall time of job.
-v|-verbose                 Give more messages.
-Z|--no-allocate            Run a job on a set of nodes with doing an actual allocation.
\n\n");

	exit;
}

##########
########## not yet, might be needed later on.
##########
#                'a|attach'        		=> \$attach_opt,
#                'A|account=s'       		=> \$account_opt,
#                'b|batch'         		=> \$batch_opt,
#                'Bextra-node-info=s' 		=> \$vextra_node_al,
#                'C|constraint=s'    		=> \$constraint_opt,
#                'd|dependency=s'    		=> \$dependent_opt,
#                'E|preserve-env'  		=> \$preserve_opt,
#                'E|preserve-flux-env' 		=> \$preserve_opt,
#                'G|geometry=s'      		=> \$geometry_opt,
#		         'gpus-per-node:s'		=> \$gpus_per_node,
#                'I|immediate:s'     		=> \$immediate_opt,
#                'join=s'          		=> \$join_opt,
#                'J|job-name=s'      		=> \$job_name_val,
#                'k|no-kill'       		=> \$no_kill_opt,
#                'K|kill-on-bad-exit:s' 		=> \$kill_on_bad_exit_opt,
#                'L|licenses=s'      		=> \$licenses_opt,
#                'L|license=s'      		=> \$licenses_opt,
#                'm|distribution=s'  		=> \$distribution_opt,
#                'O|overcommit'    		=> \$overcommit_opt,
#                'q|quit-on-interrupt' 		=> \$quiet_on_ibnterupt_opt,
#                'Q|quiet'            		=> \$quiet_opt,
#                'r|relative=s'      		=> \$relative_opt,
#                'R|no-rotate'     		=> \$no_rotate_opt,
#                's|share'         		=> \$share_opt,
#                'T|threads=s'       		=> \$threads_opt,
#                'u|unbuffered'    		=> \$unbuffered_opt,
#                'V|version'       		=> \$version_opt,
#                'w|nodelist=s'      		=> \$nodelist_opt,
#                'W|wait=s'          		=> \$wait_opt,
#                'x|exclude=s'       		=> \$exclude_opt,
#                'X|disable-status' 		=> \$disable_status_opt,
#                'acctg-freq=s'       		=> \$acct_freq_opt,
#                'alps=s'             		=> \$alps_opt,
#                'begin=s'            		=> \$beginbxopt,
#                'blrts-image=s'      		=> \$blrts_imnage_opt,
#                'checkpoint=s'       		=> \$checkpoint_opt,
#                'checkpoint-dir=s'   		=> \$checkpoint_dir_opt,
#                'cnload-image=s'     		=> \$cnloab_image_opt,
#                'cores-per-socket=s' 		=> \$cores_per_socket_opt,
#                'cpu_bind=s'         		=> \$cpu_bind_opt,
#                'debugger-test'    		=> \$debugger_test_opt,
#                'epilog=s'           		=> \$debugger_test_opt,
#                'exclusive'        		=> \$exclusive_opt,
#                'get-user-env=s'      		=> \$get_user_env_opt,
#                'gid=s'              		=> \$gid_val,
#                'gres=s'             		=> \$gres_opt,
#                'hint=s'             		=> \$hint_opt,
#                'ioload-image=s'     		=> \$ioload_images_opt,
#                'jobid=s'          		=> \$jobid_opt,
#                'linux-image=s'      		=> \$linux_image_opt,
#                'mail-type=s'        		=> \$ail_type_opt,
#                'mail-user=s'        		=> \$mail_user_opt,
#                'max-exit-timeout=s' 		=> \$mail_exit_opt,
#                'max-launch-time=s'  		=> \$mail_launch_time_opt,
#                'mem=s'              		=> \$mem_opt,
#                'mem-per-cpu=s'      		=> \$mem_per_cpu_opt,
#                'mem_bind=s'         		=> \$mem_bind_opt,
#                'mincores=s'         		=> \$mincores_opt,
#                'mincpus=s'          		=> \$mincpus_opt,
#                'minsockets=s'       		=> \$minsockets_opt,
#                'minthreads=s'       		=> \$minthreads_opt,
#                'mloader-image=s'    		=> \$mloaver_image_opt,
#                'mpi=s'              		=> \$mpi_opt,
#                'msg-timeout=s'      		=> \$msg_timeout_opt,
#                'multi-prog'       		=> \$multi_prog_opt,
#                'network=s'          		=> \$network_opt,
#                'nice:s'              		=> \$nice_opt,
#                'ntasks-per-core=s'  		=> \$ntasks_per_core_opt,
#                'ntasks-per-node=s'  		=> \$ntasks_per_node,
#                'ntasks-per-socket=s'		=> \$ntasks_per_socket_opt,
#                'open-mode=s'        		=> \$open_mode_opt,
#                'prolog=s'           		=> \$prolog_opt,
#                'propagate:s'         		=> \$propagate_opt,
#                'pty'              		=> \$pty_opt,
#                'qos=s'              		=> \$qos_opt,
#                'ramdisk-image=s'    		=> \$ramdisk_image_opt,
#                'reboot'           		=> \$reboot_opt,
#                'reservation=s'      		=> \$reservation_opt,
#                'restart-dir=s'      		=> \$restarert_dir_opt,
#                'resv-ports:s'        		=> \$resv_ports_opt,
#                'signal=s'           		=> \$signal_opt,
#                'sockets-per-node=s' 		=> \$sockets_per_node_opt,
#                'task-epilog=s'      		=> \$task_epilog_opt,
#                'task-prolog=s'      		=> \$task_prolog_opt,
#                'tasks-per-node=s'   		=> \$tasks_per_node_opt,
#                'test-only'        		=> \$test_only_opt,
#                'time-min=s'         		=> \$time_min_opt,
#                'threads-per-core=s' 		=> \$tghreads_per_core_opt,
#                'tmp=s'              		=> \$tmp_opt,
#                'uid=s'              		=> \$uid_opt,
#                'usage'            		=> \$usage_opt,
#                'wckey=s'            		=> \$wckey_opt,
