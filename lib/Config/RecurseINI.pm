package Config::RecurseINI;

use strict;
use warnings;

use base 'Exporter';
use Cwd qw(abs_path);
use Carp;

use Getopt::Long;
use Config::Tiny;

our @EXPORT_OK = qw(config debug verbose);
my %exports = map { $_ => 1 } @EXPORT_OK;

our $VERSION = '0.9.1';

my $defaultpath 	= abs_path($0);
unless ($defaultpath =~ s{/\w?bin/[^/]+$}{/config/}) {
  $defaultpath =~ s{/[^/]+$}{/};
}
my $scriptpath		= $0;
my ($scriptname)	= $scriptpath =~ m{([^/]+)$};
$scriptname =~ s{\.(pl|t)$}{};

my @configdirs  = ();
if ($ENV{HOME}) {
	push @configdirs, $ENV{HOME}, $ENV{HOME}.'/.config';
}
push @configdirs, '/etc/', $defaultpath;

my $configname	= '';

my $debug 			= -1;
my $verbose 		= -1;
my $readstrict 	= 0;

my %params=();

############################
# import
#     IN: list of subs to export
#    OUT: 
#GoodFor: import methods
sub import {
  my $class = shift;
	unless ($configname and !$exports{ $_[0] } ) {
		$configname = shift;
	}
	@_ = grep { $exports{ $_ } } @_;

	_read_config() unless %params;

	$class->Exporter::export_to_level(1, $class, @_);
}

############################
# debug
#     IN: 0 
#    OUT: $debuglevel
#GoodFor: check if debug is active
sub debug {
	_read_config() unless %params;

	return $debug;
} 

############################
# verbose
#     IN: 0 
#    OUT: $verboselevel
#GoodFor: check if verbose is active
sub verbose {
	_read_config() unless %params;

	return $verbose;
} 

############################
# config
#     IN: 
#    OUT: 
#GoodFor: 
my %config=();
sub config {
	my $section;
	my %args = ();
	if ( scalar @_ == 2 ) {
		%args = (section => shift, configkey => shift);
	} else {
		$section = shift if scalar @_ %2;
		%args = @_;
	}

	$section ||= delete $args{section};
	my $key = delete $args{configkey};
	
	_read_config(%args)
		unless %config and (!$args{strict} or $readstrict);

	my %sec = $section ? %{$config{$section}||{}} : %config;
	if ($key) {
		return $sec{$key};
	}
	
	return wantarray ? %sec : \%sec;
} 

############################
# _read_config
#     IN: %args - see docs
#    OUT: \%config
#GoodFor: Read the full configuration for a script
sub _read_config {
	my %args=@_;
	my $strict = $args{strict} || 0;

	my ($cpkg) = caller(1);
	my $checks;
	if ($args{config_check}) {
		$checks = $args{config_check}->();
	} elsif (my $chk=$cpkg->can('config_check')) {
		$checks = $chk->();
	}
	if ($strict and !$checks) {
		croak "Can't use strict mode without a config_check\n";
	}

	my %parms = get_params();
	get_env_params(\%parms);

	my $cfname = $parms{config};
	$cfname = _get_best_config() unless $cfname;

	my $cfg = Config::Tiny->read($cfname);
	unless ($cfg) {
		my $err = Config::Tiny->errstr;
		croak "Error reading config '$cfname': << $err >> " if $err;
	}

	$debug>-1 or $debug = $cfg->{_}->{debug} || 0;
	$verbose>-1 or $verbose = $cfg->{_}->{verbose} || 0;

	my %isa = ();
	for my $s (keys %$cfg) {
		next if $s eq '_';

		for my $k (keys %{$cfg->{$s}}) {
			next if $k eq '_isa';

			my $chk = $checks->{$s}->{$k};
			if ($strict and !$chk) {
				croak "config option [$s]$k not needed";
			}
			if ($chk and $chk->{check}) {
				if ($cfg->{$s}->{$k}=~$chk->{check}) {
					$config{$s}{$k} = $cfg->{$s}{$k};
				} else {
					croak "config option [$s]$k='$cfg->{$s}{$k}' is not valid";
				}
			} else {
				$config{$s}{$k} = $cfg->{$s}{$k};
			}
		}

		if ( $cfg->{ $s }->{_isa} ) {
			$isa{ $s } = [ split /\s*[,;]\s*/, $cfg->{ $s }->{_isa} ];
		}
	}

	my $_isa;
	my %_isaseen;
	$_isa = sub {
		my $s = shift;
		return if $_isaseen{ $s };
		$_isaseen{ $s }++;
		for my $ds ( @{ $isa{$s} }) {
			if ($isa{ $ds }) {
				$_isa->($ds);
			}
			for my $k (keys %{ $config{ $ds } }) {
				$config{ $s }{ $k } = $config{ $ds }{ $k }
					unless exists $config{ $s }{ $k };
			}
		}
		$_isaseen{ $s }--;
	};

	for my $s (keys %isa) {
		%_isaseen = ();
		$_isa->($s) if $isa{ $s };
	}

	if ($checks) {
		for my $s (keys %$checks) {
			for my $k (keys %{$checks->{$s}}) {
				$config{$s}{$k} = $checks->{$s}{$k}{default}
					if (exists $checks->{$s}{$k}{default}
						and !exists $config{$s}{$k});

				croak "Missing config option [$s]$k"
					if $checks->{$s}{$k}{needed}
						and !exists $config{$s}{$k};
			}
		}
	}

}

############################
# _get_best_config
#     IN: 0
#    OUT: filename for the config file
#GoodFor: find the config file name
sub _get_best_config {
	carp "Can't guess the config file for -e [use --config]"
		if !$configname and $scriptname eq '-e';

  $configname ||= $scriptname;

	for my $dir (@configdirs) {
    next unless -d $dir;

		my @fnames = ("$configname.ini", "$configname.conf");
		unshift @fnames, ".$configname" if $dir eq $ENV{HOME}//'';

    $dir .= '/' unless substr($dir, -1) eq '/';
    for my $cfgname (@fnames) {
      $cfgname = $dir.$cfgname;
  		$debug>4 and print STDERR "trying configfile=$cfgname\n";
	  	if (-r $cfgname) {
		  	$verbose>2 and print STDERR "guessed configfile='$cfgname'\n";
			  return $cfgname;
		  }
    }
	}

	croak "Unable to guess a config file for '$scriptname'";
} 

############################
# get_params
#     IN: 0
#    OUT: %params
#GoodFor: Get the params that the script got
sub get_params {
	return %params if %params;
	%params=(config=>'',setconfig=>{});
	GetOptions(
		#config params
		"config=s"	=> \$params{config},
		"setconfig=s%" => $params{setconfig},

		#debug and info
		"debug=i"		=> \$debug,
		"nodebug"		=> sub { $debug=0 },
		"verbose=i"	=> \$verbose,
		"noverbose"	=> sub { $verbose=0 },
	);

	return %params;
} 

############################
# get_env_params
#     IN: \%params
#    OUT: 0
#GoodFor: get params from %ENV
sub get_env_params {
	my $parms=shift;

	$parms->{config} ||= $ENV{'CONFIG_FILE'} || '';
	$debug  	= $ENV{'DEBUG'}
		if $debug<0 and exists $ENV{'DEBUG'};
	$verbose	= $ENV{'VERBOSE'}
		if $verbose<0 and exists $ENV{'VERBOSE'};
} 

1;
__END__

=head1 NAME

Config::RecurseINI - some extras on top of Config::Tiny

=head1 SYNOPSIS

    use Config::RecurseINI 'someapp' => qw(config);

    my $dbname = config('database','dbname');
    my %dbconfig = config('database');

=head1 DESCRIPTION

Config::RecuseINI adds two main things on top of Config::Tiny:

=over 4

=item Config Inheritance

You can define one section as being the same as other section with
some extras (or overrides):

  [dabatase]
  hostname=127.0.0.1
  username=dbuser
  password=passwd

  [database:users]
  _isa=database
  dbname=user

  [database:posts]
  _isa=database
  dbname=posts

when calling config('database:users') config::RecurseINI will return

   {  hostname  => '127.0.0.1',
      username  => 'dbuser',
      password  => 'passwd',
      dbname    => 'user',
   }

=item Config Discovery

Config::RecurseINI looks for the config file - see bellow L<config-name> -
in several places, in order:

=over 4

=item - $HOME/

if the env variable $HOME is defined, it will look for a file named
.<config-name> - this is the only e

=item - $HOME/.config/

=item - /etc/

=item - .../config/

if $0 is in a .../bin/ or .../?bin/ directory, it looks for a config file
in a config directory in the parent of that directory.

=back

=back

=head2 config-name

the first time you use Config::RecurseINI you can define what is the name
of the config file if that is not given, the basename of $0 will be used

example:

  use Config::RecurseINI 'someapp' => qw(config);

either way, that will be only the basename of the config file, and the
name will be appended with .ini or .conf - both will be search for, in
that order.

=head1 METHODS

=head2 config($section[, $key])

config can take one or two parameters - the first will return a full config
section, while the second will return the value of a specific config key
in that section.

In case of usage with only one parameter, config will return an HASH or
an hashref, depending on context.

=head2 debug

Config::RecurseINI uses several different ways to define what debug level
will be used: env $DEBUG, the parameter --debug or the debug key in the
root of your config file.

=head2 versbose

the same as with debug, $VERBOSE, --verbose and verbose key in the root
section.

=head1 BUG REPORTS and FEATURE REQUESTS

Please report any bugs or request features in:

=over 4

=item github: https://github.com/themage/perl-config-recurseini

=item Magick Source: http://magick-source.net/MagickPerl/Config-RecurseINI

=back

=head1 AUTHOR

theMage E<lt>themage@magick-source.netE<gt>

=head1 COPYRIGHT and LICENSE

Copyright (C) 2016 by theMage

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.22.1 or,
at your option, any later version of Perl 5 you may have available.

Alternativally, you can also redistribute it and/or modify it
under the terms of the GPL 2.0 licence (or any future version of it).

=cut

