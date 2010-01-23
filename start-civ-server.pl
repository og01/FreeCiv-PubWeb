#!/usr/bin/perl

use strict;
use warnings;

use DateTime;
use Config::Simple;
use Path::Class;
use Unix::PID;
use Time::Interval;
use File::Touch;
use POSIX ":sys_wait_h";
#use Proc::ProcessTable::Process;

# find where we live
use FindBin qw($Bin);
# include our lib search path
use lib dir($Bin, "lib")->stringify;

use FreeCiv;

my $dir_base =  dir($ENV{"HOME"}, "FreeCiv-PubWeb");
my $file_auth = file($dir_base, "fc_auth.conf");
my $file_serversetttings = file($dir_base, "serversettings.serv");

my $pid_obj = Unix::PID->new();

# Create Objects
my $cfg = new Config::Simple(file($dir_base, 'civ.cfg'));

# Create Base Directories

sub isint{
  my $val = shift;
  return ($val =~ m/^\d+$/);
}

my $id;
if ($#ARGV+1 == 1) {
	$id = $ARGV[0];
}
elsif ($#ARGV+1 == 0) {
	$id = $cfg->param('Last_Game_ID') + 1 or $id = 1;
}
else {
	print "\nUsage:\n\n";
	print "start-civ-server.pl [gameid]\n";
	print "\n";
	exit;
}


my @ports;

if (defined $cfg->param('Avaliable_Ports')) {
	@ports = split(' ', $cfg->param('Avaliable_Ports')); 
}
else {
	@ports = (5556..5565);
}

if (isint($ports[$#ports])) { # Port to be popped sanity check

	my $fc = FreeCiv->new({turns => 0});

	print "Game ID: $id\n";
	print "Avaliable Ports: " . @ports  . "\n";
	$fc->{port} = pop(@ports);

	$cfg->param('Avaliable_Ports', "@ports");
	$cfg->param('Last_Game_ID', $id);
	$cfg->save();

	my $dir_log = dir($dir_base, "logs", $id);
	my $dir_save = dir($dir_base, "savegames", $id);
	my $file_rank_log = file($dir_log, "rank.log"); 
	my $file_game_log = file($dir_log, "game.log");
	my $file_server_output = file($dir_log, "server.output");
	my $file_script_output = file($dir_log, "script.pl");
	$dir_log->mkpath() unless -d $dir_log;
	$dir_save->mkpath() unless -d $dir_save;

	#touch($file_rank_log);
	#touch($file_game_log);
	#touch($file_server_output);
	## No Longer need to touch or otherwise populate files. I think.
	#open FILE, ">", $file_game_log  or die $!;
	#print FILE "Prepairing log file for pubweb\n";
	#close FILE;

	my $pid = fork();
	if ($pid == -1 ) {
		die "could not fork $!";
	} elsif ($pid == 0 ) {
		# child 
		close STDOUT;
		close STDIN;
		close STDERR;
		exec ("civserver -N -P -e -p $fc->{port} -a $file_auth -r $file_serversetttings -R  $file_rank_log -s $dir_save -d 3 -l $file_game_log > $file_server_output");
	
	} else {
		# parent
		print "child server is running with pid = $pid\n";
		
		$fc->loadfile({log_file => $file_game_log} ); # open gamelog file for tail

		$fc->{serverrunning} = 1;

		$fc->dumpoutput({output_filename => $file_script_output});

		my $timer = DateTime->now(); # start timer
		print "Entering loop\n";
		while (kill(0, $pid)) { # Is child (civserver) process alive?
			if (getInterval($timer, DateTime->now())->{seconds} > 5) { # wait 5 seconds
				$fc->readlines; # process all new lines
				$timer = DateTime->now(); # Reset timer
				$fc->dumpoutput({output_filename => $file_script_output});
			}
			waitpid(-1, WNOHANG);  ## This clears the zombies with hanging.
		}

		$fc->readlines;
				
		$fc->dumpoutput({output_filename => $file_script_output});

		# Server has stopped - Release port for new servers to use.
		@ports = split(' ', $cfg->param('Avaliable_Ports'));
		push (@ports, $fc->{port});
		$cfg->param('Avaliable_Ports', "@ports");
		$cfg->save();
	}
	
}
else {
	print "All game slots are full.\n";
}

#civserver -N -P -e -p 5558 -a ~/.freeciv/fc_auth.conf -r ~/.freeciv/serversettings -R ~/.freeciv/ranklog5558 -s ~/.freeciv/savegames5558 -d 4 -l ~/.freeciv/logs/game5558.log -R ~/.freeciv/logs/rank.log 
