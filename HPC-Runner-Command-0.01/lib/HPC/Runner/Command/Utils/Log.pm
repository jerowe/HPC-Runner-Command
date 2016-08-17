package HPC::Runner::Command::Utils::Log;

use Log::Log4perl qw(:easy);
use Data::Dumper;
use IPC::Open3;
use IO::Select;
use Symbol;
use Log::Log4perl qw(:easy);
use DateTime;
use DateTime::Format::Duration;
use Cwd;
use File::Path qw(make_path);
use File::Spec;

use MooseX::App::Role;
use MooseX::Types::Path::Tiny qw/Path Paths AbsPath AbsFile/;

=head1 HPC::Runner::App::Log

Class for all logging attributes

=head2 Command Line Options


=head3 logdir

Pattern to use to write out logs directory. Defaults to outdir/prunner_current_date_time/log1 .. log2 .. log3.

=cut

option 'logdir' => (
    is       => 'rw',
    isa      => AbsPath,
    coerce   => 1,
    lazy     => 1,
    required => 1,
    default  => \&set_logdir,
    documentation =>
        q{Directory where logfiles are written. Defaults to current_working_directory/prunner_current_date_time/log1 .. log2 .. log3'},
    trigger => \&_make_the_dirs,
);

=head3 show_process_id

Show process_id in each log file. This is useful for aggregating logs

=cut

option 'show_processid' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        q{Show the process ID per logging message. This is useful when aggregating logs.}
);

=head3 process_table

We also want to write all cmds and exit codes to a table

=cut

option 'process_table' => (
    isa     => 'Str',
    is      => 'rw',
    handles => {
        add_process_table     => 'append',
        prepend_process_table => 'prepend',
        clear_process_table   => 'clear',
    },
    default => sub {
        my $self = shift;
        return $self->logdir . "/001-process_table.md";
    },
    lazy => 1,
);

=head3 metastr

JSON string passed from HPC::Runner::App::Scheduler. It describes the total number of jobs, processes, and job batches.

=cut

option 'metastr' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => q{Meta str passed from HPC::Runner::Scheduler},
    required      => 0,
);

option 'logname' => (
    isa      => 'Str',
    is       => 'rw',
    default  => 'hpcrunner_logs',
    required => 0,
);

=head2 Internal Attributes

You shouldn't be calling these directly.

=cut

has 'dt' => (
    is      => 'rw',
    isa     => 'DateTime',
    default => sub { return DateTime->now( time_zone => 'local' ); },
    lazy    => 1,
);

#TODO Change to submit_log and execute_log

has 'log' => ( is => 'rw', );

has 'command_log' => ( is => 'rw', );

has 'app_log' => (
    is      => 'rw',
    default => sub {
        my $self = shift;

        return Log::Log4perl->init( \ <<'EOT');
  log4perl.category = DEBUG, Screen
  log4perl.appender.Screen = \
      Log::Log4perl::Appender::ScreenColoredLevels
  log4perl.appender.Screen.layout = \
      Log::Log4perl::Layout::PatternLayout
  log4perl.appender.Screen.layout.ConversionPattern = \
      [%d] %m %n
EOT
        }

);

has 'logfile' => (
    traits  => ['String'],
    is      => 'rw',
    default => \&set_logfile,
    handles => {
        append_logfile  => 'append',
        prepend_logfile => 'prepend',
        clear_logfile   => 'clear',
    }
);

has 'job_tags' => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
    handles => {
        set_job_tag     => 'set',
        get_job_tag     => 'get',
        has_no_job_tags => 'is_empty',
        num_job_tags    => 'count',
        delete_job_tag  => 'delete',
        job_tag_pairs   => 'kv',
    },
);

=head3 table_data

Each time we make an update to the table throw it in here

=cut

has 'table_data' => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
    handles => {
        set_table_data    => 'set',
        get_table_data    => 'get',
        delete_table_data => 'delete',
        has_no_table_data => 'is_empty',
        num_table_data    => 'count',
        table_data_pairs  => 'kv',
        clear_table_data  => 'clear',
    },
);

=head2 Subroutines

=head3 set_logdir

Set the log directory

=cut

sub set_logdir {
    my $self = shift;

    my $logdir;

    #TODO Add in Version
    if ( $self->has_version && $self->has_git ) {
        $logdir
            = "hpc-runner/"
            . $self->version . "/logs" . "/"
            . $self->set_logfile . "-"
            . $self->logname;
    }
    else {
        $logdir
            = "hpc-runner/logs" . "/"
            . $self->set_logfile . "-"
            . $self->logname;
    }
    $logdir =~ s/\.log$//;

    $self->_make_the_dirs($logdir);

    return $logdir;
}

=head3 set_logfile

Set logfile

=cut

sub set_logfile {
    my $self = shift;

    my $tt = DateTime->now( time_zone => 'local' )->ymd();
    return "$tt";
}

=head3 init_log

Initialize Log4perl log

=cut

sub init_log {
    my $self = shift;

    Log::Log4perl->easy_init(
        {   level  => $TRACE,
            utf8   => 1,
            mode   => 'append',
            file   => ">>" . $self->logdir . "/" . $self->logfile,
            layout => '%d: %p %m%n '
        }
    );

    my $log = get_logger();
    return $log;
}

#TODO Move this to App/execute_job/Log ... something to mark that this logs the
#individual processes that are executed

=head3 _log_commands

Log the commands run them. Cat stdout/err with IO::Select so we hopefully don't break things.

This example was just about 100% from the following perlmonks discussions.

http://www.perlmonks.org/?node_id=151886

You can use the script at the top to test the runner. Just download it, make it executable, and put it in the infile as

perl command.pl 1
perl command.pl 2
#so on and so forth

=cut

#TODO move to execute_jobs

sub _log_commands {
    my ( $self, $pid ) = @_;

    my $dt1 = DateTime->now( time_zone => 'local' );

    $DB::single = 2;

    my ( $cmdpid, $exitcode ) = $self->log_job;

    my $ymd = $dt1->ymd();
    my $hms = $dt1->hms();

    #TODO Make table data its own class and return it
    $self->clear_table_data;
    $self->set_table_data( cmdpid     => $cmdpid );
    $self->set_table_data( start_time => "$ymd $hms" );

    my $meta = $self->pop_note_meta;
    $self->set_job_tag( cmdpid => $meta ) if $meta;

    $self->log_cmd_messages( "info",
        "Finishing job " . $self->counter . " with ExitCode $exitcode",
        $cmdpid );

    my $dt2      = DateTime->now();
    my $duration = $dt2 - $dt1;
    my $format
        = DateTime::Format::Duration->new( pattern =>
            '%Y years, %m months, %e days, %H hours, %M minutes, %S seconds'
        );

    $self->log_cmd_messages( "info",
        "Total execution time " . $format->format_duration($duration),
        $cmdpid );

    $self->log_table( $cmdpid, $exitcode,
        $format->format_duration($duration) );

    return $exitcode;
}

=head3 name_log

Default is dt, jobname, counter

=cut

sub name_log {
    my $self   = shift;
    my $cmdpid = shift;

    my $counter = $self->counter;

    $self->logfile( $self->set_logfile );
    $counter = sprintf( "%03d", $counter );
    $self->append_logfile( "-CMD_" . $counter . "-PID_$cmdpid.md" );

    $self->set_job_tag( "$counter" => $cmdpid );
}

#TODO move to execute_jobs

sub log_table {
    my $self     = shift;
    my $cmdpid   = shift;
    my $exitcode = shift;
    my $duration = shift;

    my $dt1 = DateTime->now( time_zone => 'local' );
    my $ymd = $dt1->ymd();
    my $hms = $dt1->hms();

    $self->set_table_data( exit_time => "$ymd $hms" );
    $self->set_table_data( exitcode  => $exitcode );
    $self->set_table_data( duration  => $duration );

    my $version = $self->version || "0.0";
    my $job_tags = "";

    my $logfile = $self->logdir . "/" . $self->logfile;

    open( my $pidtablefh, ">>" . $self->process_table )
        or die $self->app_log->fatal("Couldn't open process file $!\n");

    #or die print "Couldn't open process file $!\n";

    if ( $self->can('job_tags') ) {
        my $aref = $self->get_job_tag($cmdpid) // [];
        $job_tags = join( ", ", @{$aref} ) || "";

        $self->set_table_data( job_tags => $job_tags );
    }

    if ( $self->can('version') && $self->has_version ) {
        $version = $self->version;
        $self->set_table_data( version => $version );
    }

    if ( $self->can('job_scheduler_id') && $self->can('jobname') ) {
        my $schedulerid = $self->job_scheduler_id || '';
        my $jobname     = $self->jobname          || '';
        print $pidtablefh <<EOF;
|$version|$schedulerid|$jobname|$job_tags|$cmdpid|$exitcode|$duration|
EOF

        $self->set_table_data( schedulerid => $schedulerid );
        $self->set_table_data( jobname     => $jobname );
    }
    else {
        print $pidtablefh <<EOF;
|$cmdpid|$exitcode|$duration|
EOF
    }
}

#TODO move to execute_jobs

sub log_cmd_messages {
    my ( $self, $level, $message, $cmdpid ) = @_;

    return unless $message;

    if ( $self->show_processid && $cmdpid ) {
        $self->command_log->$level("PID: $cmdpid\t$message");
    }
    else {
        $self->command_log->$level($message);
    }
}

sub log_main_messages {
    my ( $self, $level, $message ) = @_;

    return unless $message;
    $level = 'debug' unless $level;
    $self->log->$level($message);
}

sub log_job {
    my $self = shift;

    #Start running job
    my ( $infh, $outfh, $errfh );
    $errfh = gensym();    # if you uncomment this line, $errfh will
    my $cmdpid;
    eval { $cmdpid = open3( $infh, $outfh, $errfh, $self->cmd ); };

    if ($@) {
        die $self->app_log->fatal(
            "There was an error running the command $@\n");
    }

    if ( !$cmdpid ) {

#print
#"There is no $cmdpid please contact your administrator with the full command given\n";
        $self->app_log->fatal(
            "There is no process id please contact your administrator with the full command\n"
        );
        die;
    }
    $infh->autoflush();

    $self->name_log($cmdpid);
    $self->command_log( $self->init_log );

    $DB::single = 2;

    $self->log_cmd_messages( "info",
        "Starting Job: " . $self->counter . " \nCmd is " . $self->cmd,
        $cmdpid );

    $DB::single = 2;

    my $sel = new IO::Select;    # create a select object
    $sel->add( $outfh, $errfh ); # and add the fhs

    while ( my @ready = $sel->can_read ) {
        foreach my $fh (@ready) {    # loop through them
            my $line;

            # read up to 4096 bytes from this fh.
            my $len = sysread $fh, $line, 4096;
            if ( not defined $len ) {

                # There was an error reading
                $self->log_cmd_messages( "fatal", "Error from child: $!",
                    $cmdpid );
            }
            elsif ( $len == 0 ) {

                # Finished reading from this FH because we read
                # 0 bytes.  Remove this handle from $sel.
                $sel->remove($fh);
                next;
            }
            else {    # we read data alright
                if ( $fh == $outfh ) {
                    $self->log_cmd_messages( "info", $line, $cmdpid );
                }
                elsif ( $fh == $errfh ) {
                    $self->log_cmd_messages( "error", $line, $cmdpid );
                }
                else {
                    $self->log_cmd_messages( 'fatal',
                        "Shouldn't be here!\n" );
                }
            }
        }
    }

    waitpid( $cmdpid, 1 );
    my $exitcode = $?;

    return ( $cmdpid, $exitcode );
}

#TODO Write Tests

sub pop_note_meta {
    my $self = shift;

    my $lines = $self->cmd;
    return unless $lines;
    my @lines = split( "\n", $lines );
    my @ts = ();

    foreach my $line (@lines) {
        next unless $line;
        next unless $line =~ m/^#NOTE/;

        my ( @match, $t1, $t2 );
        @match = $line =~ m/NOTE (\w+)=(.+)$/;
        ( $t1, $t2 ) = ( $match[0], $match[1] );

        $DB::single = 2;
        if ($t1) {
            if ( $t1 eq "job_tags" ) {
                my @tmp = split( ",", $t2 );
                map { push( @ts, $_ ) } @tmp;
            }
            else {
                #We should give a warning here
                $self->$t1($t2);
                $self->log_main_messages( 'debug',
                          "Command:\n\t"
                        . $self->cmd
                        . "\nHas invalid #NOTE attribute. Should be #NOTE job_tags=thing1,thing2"
                );
            }
        }
    }
    return \@ts;
}

1;
