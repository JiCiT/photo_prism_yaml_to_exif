use strict;
use v5.12;

use Log::ger::Output 'Screen';
use Log::ger::Util;
use Log::ger;
use Getopt::Simple qw($switch);
use Privileges::Drop;
use Cwd;
use File::Find;
use File::Basename;
use File::Path qw(make_path);
use File::Copy qw(move);

# define available arguments
my $args = {
      help                  => {
          type      => ''
        , env       => '-'
        , default   => ''
        , verbose   => ''
        , order     => 1
      }
    , log_level             => {
          type      => '=s'
        , env       => 'LOG_LEVEL'
        , default   => $ENV{'LOG_LEVEL'} || 'warn'
        , verbose   => 'Set logging level'
        , order     => 'debug'
      }
    , yaml_dir              => {
          type      => '=s'
        , env       => '-'
        , default   => cwd()
        , verbose   => 'Root directory with PhotoPrism YAML sidecar files'
        , order     => 2
      }
    , image_dir         => {
          type      => '=s'
        , env       => '-'
        , default   => cwd()
        , verbose   => 'Root directory with original image files'
        , order     => 3
      }
    , uid                   => {
          type      => '=i'
        , env       => '-'
        , default   => $<                                                   # Effective UID
        , verbose   => 'UserId for file owner (chown)'
        , order     => 4
      }
    , gid                   => {
          type      => '=i'
        , env       => '-'
        , default   => $>                                                   # Effective GID
        , verbose   => 'GroupId for file owner (chown)'
        , order     => 5
      }
};

# get ref to an argument parser
my $arg = Getopt::Simple->new();

# parse given arguments in relation to defined options
if (! $arg->getOptions($args, "Usage: PhotoPrism_YAML_to_EXIM.pl [args]")) {
    exit (-1);
}

# get more convienent ref to supplied arguments
my $args = $arg->{'switch'};

# set log level from CLI args
Log::ger::Util::set_level($args->{'log_level'});

# set UID
if (exists $args->{'uid'} && $args->{'uid'} !~ /^\d+$/) {
    $args->{'uid'} = getpwnam($args->{'uid'});
}

# set GID
if (exists $args->{'gid'} && $args->{'gid'} !~ /^\d+$/) {
    $args->{'gid'} = getpwnam($args->{'gid'});
}

# Drop Privileges
log_info('Dropping privleges to %i:%i', $args->{'uid'}, $args->{'gid'});
drop_uidgid($args->{'uid'}, $args->{'gid'});

# loop through YAML files
sub process_file {
    # get a more descriptivie reference to the image file
    my $filename_yaml = $_;
    log_trace('$filename_image: "%s"', $filename_yaml);
    
    # get absolute path to yaml
    my $abs_path_yaml = $File::Find::dir;
    log_trace('$abs_path_yaml: "%s"', $abs_path_yaml);
    
    # get relative directory to yaml
    my $rel_path_yaml = $abs_path_yaml =~ s/^\Q$args->{'yaml_dir'}\E\/?//r;
    log_trace('$rel_path_yaml: "%s"', $rel_path_yaml);

    # skip root (.) and parent (..) directories
    if ($filename_yaml =~ /^\.{1,2}$/) {
        log_debug('skipping: current or root directory');
        return;
    }

    # skip other directories
    if (-d $abs_path_yaml . '/' . $filename_yaml) {
        log_debug('skipping: directory');
        return;
    }
    
    # if current file is a YAML file..
    if ($filename_yaml =~ /\.yml$/) {
        #... get basename for yaml file
        my $filename_yaml_base = $filename_yaml =~ s/\.yml//r;
        log_trace('$filename_yaml_base: "%s"', $filename_yaml_base);
        
        # search the image_dir for files with the same basename
        my @candidates = glob('"' . $args->{'image_dir'} . '/' . $filename_yaml_base . '."*');
        log_trace('Candidates: %s', @candidates);
        
        # loop through all the candidate files
        foreach my $candidate (@candidates) {
            my $file_name_candidate = basename($candidate);
            log_trace('$file_name_candidate: "%s"', $file_name_candidate);
            # make $rel_path_yaml directory inside $args->{'image_dir'} unless it's already a directory
            unless (-d $args->{'image_dir'} . '/' . $rel_path_yaml) {
                make_path($args->{'image_dir'} . '/' . $rel_path_yaml, {error => \my $err});
                if ($err && @$err) {
                    for my $diag (@$err) {
                        my ($file, $message) = %$diag;
                        if ($file eq '') {
                            log_error('general error: %s', $message);
                        }
                        else {
                            log_error('problem creating path: "%s"', $message);
                        }
                    }
                }
                else {
                    log_info('Created directory "%s"', $args->{'image_dir'} . '/' . $rel_path_yaml);
                }
            }
            log_info('Moving "%s" to "%s"', $candidate, $args->{'image_dir'} . '/' . $rel_path_yaml . '/' . $file_name_candidate);            
            move($candidate, $args->{'image_dir'} . '/' . $rel_path_yaml . '/' . $file_name_candidate) or die $!;
        }
    }
}

# Recurse through YAML dir
log_debug('Processing image dir "%s"', $args->{'yaml_dir'});
find(\&process_file, ($args->{'yaml_dir'}));

exit(0);