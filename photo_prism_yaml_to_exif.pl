use strict;
use v5.38;
use feature 'try';

use Log::ger::Output 'Screen';
use Log::ger::Util;
use Log::ger;
use Cwd;
use DateTime;
use DateTime::Format::EXIF;
use File::Basename;
use File::Find;
use File::Spec;
use File::stat;
use Getopt::Long::Descriptive;
use Image::ExifTool;
use List::Util qw(min);
use Privileges::Drop;
use YAML::PP;
use Data::Dumper;

# define available arguments
my @opt_spec = (
      [
          'log_level|ll=s'
        , 'Logging level.  DEFAULT: ( $ENV{\'PPYX_LOG_LEVEL\'} || info)'
        , { default         => ( $ENV{'PPYX_LOG_LEVEL'} || 'info' ) }
      ]
    , [
          'yaml_dir|yd=s'
        , 'Root direcotry with PhotoPrism YAML sidecard files.  DEFAULT: $ENV{\'PPYX_YAML_DIR\'} || cwd()'
        , { default         => ( $ENV{'PPYX_YAML_DIR'} || cwd() ) }
      ]
    , [
          'image_dir|id=s'
        , 'Root directory with original image files.  DEFAULT: ( $ENV{\'PPYX_IMAGE_DIR\'} || cwd() )'
        , { default         => ( $ENV{'PPYX_IMAGE_DIR'} || cwd() ) }
      ]
    , [
          'ignore_dir|xd:s@'
        , => 'Directory to ignore. May be lsited multiple times.'
      ]
    , [
          'dirs_ignore|dsx:s{,}'
        , => 'Space delimited list of directories to ignore.  DEFAULT: ( $ENV{\'PPYX_DIRS_IGNORE\'} || [] )'
        , { default         => ( $ENV{'PPYX_DIRS_IGNORE'} || [] ) }
      ]
    , [
          'image_regex|ir:s@'
        , 'Regular expression to match against file name for processing.  May be listed multiple times.  NOTE: Match against *any* listed regex will be processed.'
        , { default         => ['.+'] }
      ]
    , [
          'cmp_mtime|cmt!'
        , 'Compare image and YAML file mtimes.  DEFAULT: false'
        , { default         => 0 }
    , ]
    , [
          'user_id|uid=i'
        , 'User ID to run as.  DEFAULT: ( $ENV{\'PPYX_UID\'} | $EUID )'
        , { default         => ( $ENV{'PPYX_UID'} || $> ) }
      ]
    , [
          'group_id|gid=i'
        , 'Group ID to run as.  DEFAULT: ( $ENV{\'PPYX_GID\'} | $EGID )'
        , { default         => ( $ENV{'PPYX_GID'} || $) ) }
      ]
    , [
          'reprocess_originals|rpo!'
        , 'Reprocess original files. DEFAULT: false'
        , { default         => 0 }
      ]
    , [
          'lattitude|lat!'
        , 'add/adjust lattitude.  DEFAULT: true'
        , { default         => 1 }
      ]
    , [
          'longitude|long!'
        , 'Add/adjust longitude.  DEFAULT: true'
        , { default         => 1 }
      ]
    , [
          'altitude|alt!'
        , 'Add/adjust altitude.  DEFAULT: true'
        , { default         => 1 }
      ]
     , [
          'datetime_original|dto!'
        , 'Add/adjust datetime_originial.  DEFAULT: true'
        , { default         => 1 }
      ]
    , [
          'create_date|cdt!'
        , 'Add/adjust create_date.  DEFAULT: true'
        , { default         => 1 }
      ]
    , [
          'dry_run|dr!'
        , 'Say what would be done, but don\'t actually do it.  DEFAULT: false'
        , { default         => 0 }
      ]
    , [
          'help'
        , 'Print usage message and exit.'
        , { shortcircuit    => 1 }
      ]
);

my ($opt, $usage) = describe_options(
      '%c %o'
    , @opt_spec
    , {
          getopt_conf       => ['no_bundling']
        , show_defaults     => 1
      }
);

if ($opt->help) {
    print($usage->text);
    exit(0);
}

# set log level from CLI opt
Log::ger::Util::set_level($opt->{'log_level'});

# set UID
if (exists $opt->{'user_id'} && $opt->{'user_id'} !~ /^\d+$/) {
    $opt->{'user_id'} = getpwnam($opt->{'user_id'});
}

# set GID
if (exists $opt->{'group_id'} && $opt->{'group_id'} !~ /^[\d\s]+$/) {
    $opt->{'group_id'} = getpwnam($opt->{'group_id'});
} else {
    # get just the first group if more than one is listed
    $opt->{'group_id'} =~ s/\s.*$//;
}

# set image_regex
if (scalar(@{$opt->{'image_regex'}}) == 0) {
    $opt->{'image_regex'} = ['.+'];
}

log_debug('supplied options');
foreach my $key (keys %{$opt}) {
    if (ref($opt->{$key}) eq 'ARRAY') {
        log_debug($key . ' : ' . join(' : ', @{$opt->{$key}}));
    } else {
        log_debug($key . ' : ' . $opt->{$key});
    }
}

# Drop Privileges
if (
       ( exists $opt->{'user_id'}  && $opt->{'user_id'}  != $> )
    || ( exists $opt->{'group_id'} && $opt->{'group_id'} != $) )
) {
    log_info('dropping privleges to %i:%i', $opt->{'user_id'}, $opt->{'group_id'});
    drop_uidgid($opt->{'user_id'}, $opt->{'group_id'});
}

# create a list of directories to skip
my %_skip_dirs;
{
    for my $dir (@{$opt->{'ignore_dir'}}) {
        $_skip_dirs{$dir} = 1;
    }
    for my $dir (@{$opt->{'dirs_ignore'}}) {
        $_skip_dirs{$dir} = 1;
    }
}

# create a list of image regexes
my @_image_regexes;
for my $regex (@{$opt->{image_regex}}) {
    push(@_image_regexes, qr/$regex/);
}

# Set up YAML parser
my $ypp = YAML::PP->new;

# set up an EXIF tool
my $exif_tool = Image::ExifTool->new;

# take actions as appropriate an the supplied file
sub process_file {
    # get a more descriptive reference to the image file
    my $filename_image = $_;
    log_trace('process_file: $filename_image: "%s"', $filename_image);

    # get absolute path to image
    my $abs_path_image = File::Spec->catfile($File::Find::dir, $filename_image);
    log_debug('process_file: evaluating path "%s"', $abs_path_image);

    # skip directories
    if (-d $abs_path_image) {
        log_debug('process file: eval result: skipping: directory');
        return;
    }

    # skip backup files
    if ($filename_image =~ /\.bak(?:_\d+)*$/) {
        log_debug('process file: eval result: skipping: backup');
        return;
    }

    # if current file is an original file..
    if ($filename_image =~ /\.orig$/) {
        log_debug('process file: eval result: original file (*.orig)');

        # ...if reprocessing originals...
        if ($opt->{'reprocess_originals'}) {
            log_debug('process file: $opt->{\'reprocess_originals\'}: true :: processing');

            # get absolute path to "base" filename
            my $abs_path_base = $abs_path_image =~ s/\.orig$//r;

            # remove "base" file
            # if the base file exists...
            if (-f $abs_path_base) {
                # ...remove it
                log_debug('process_file: Removing current base file "%s"', $abs_path_base);
                unless (unlink $abs_path_base) {
                    log_error('Unable to delete exisitng replacement file: "%s"', $abs_path_base);
                    return;
                }
            }

            # rename the original file back to its base name
            log_debug('process_file: Renaming original file back to "%s"', $abs_path_base);
            unless(rename($abs_path_image, $abs_path_base)) {
                log_error('Unable to rename "%s" to "%s"', $abs_path_image, $abs_path_base);
                return;
            }

            $abs_path_image = $abs_path_base;

            # rename original file to base name
        # ...if *not* reprocessing originals...
        } else {
            #...skip it
            log_debug('process file: $opt->{\'reprocess_originals\'}: false :: skipping');
            return;
        }
    # if current files is *not* an original file...
    } else {
        #...if reprocessing originals...
        if ($opt->{'reprocess_originals'}) {
            #...skip it
            log_debug('process_file: skipping: non-original');
            return;
        #...if *not* reprocessing originals...
        } else {
            # ...if an original file exists...
            if (-f $abs_path_image . '.orig') {
                # ...skip this file
                log_debug('process_file: skipping: original file exists');
                return;
            }
        }
    }

    # get the yaml filename for the image file...
    my $filename_yaml = $filename_image =~ s/\.[^.]+$/.yml/r;
    log_trace('process_file: $filename_yaml: "%s"', $filename_yaml);

    # get the full path to the YAML file
    # 1. strip off the "root" of the image_dir path
    my $sub_dirs = $File::Find::dir =~ s/^\Q$opt->{'image_dir'}//r;
    log_trace('process_file: $sub_dirs = "%s"', $sub_dirs);
    # 2. join together the "yaml_path" , sub-dirs from step 1, and the filename.yml
    my $abs_path_yaml = File::Spec->catfile($opt->{'yaml_dir'}, $sub_dirs, $filename_yaml);
    log_trace('process_file: $abs_path_yaml: "%s"', $abs_path_yaml);
    log_debug('process_file: searching for YAML file "%s"', $abs_path_yaml);

    # verify that a YAML file exits
    log_trace('process_file: checking if $abs_path_yaml "%s" is a file', $abs_path_yaml);
    if (-f $abs_path_yaml) {
        log_debug('process_file: found YAML file "%s"', $abs_path_yaml);

        # if we are comparing image and YAML mtimes...
        if ($opt->{'cmp_mtime'}) {
            log_trace('process_file: comparing image and YAML mtimes');

            # get YAML stats
            my $yaml_stat = stat($abs_path_yaml) or die $!;
            # get image stats
            my $image_stat = stat($abs_path_image) or die $!;

            # if YAML mtime > image mtime...
            if ($yaml_stat->mtime > $image_stat->mtime) {
                # log the fact
                log_trace('process_file: YAML newer than image: processing image');
            # otherwise...
            } else {
                log_trace('process_file: YAML older than image: NOT processing image');
                # skip to the next file;
                return;
            }
        }

        # parse the YAML file into a perl data structure
        log_debug('process_file: Loading YAML data');
        my $data_yaml = $ypp->load_file($abs_path_yaml);

        # clear any previous set values in exif tool
        log_trace('process_file: clearing old set exiftool set values');
        $exif_tool->SetNewValue();

        # get EXIF info for the corresponding image file
        log_trace('process_file: parsing EXIF data into $data_exif');
        my $data_exif = $exif_tool->ImageInfo($abs_path_image);

        # LATITUDE
        # if...
        log_trace('process_file: checking if latitude set in YAML, but not in EXIF');
        if (
                #...YAML has Lat and...
                $data_yaml->{'Lat'}
                #...EXIF does NOT have GPSLatitude...
            &&  (! $data_exif->{'GPSLatitude'})
        ) {
            #... set the latitude
            log_debug('process_file: setting EXIF latitude to %s', $data_yaml->{'Lat'});
            $exif_tool->SetNewValue('GPSLatitude*', $data_yaml->{'Lat'});
        }

        # LONGITUDE
        # if...
        log_trace('process_file: checking if longitude set in YAML, but not in EXIF');
        if (
                #...YAML has Lng and...
                $data_yaml->{'Lng'}
                #...EXIF does NOT have GPSLongitude...
                &&  (! $data_exif->{'GPSLongitude'})
        ) {
            # set the longitude
            log_debug('process_file: setting EXIF longitude to %s', $data_yaml->{'Lng'});
            $exif_tool->SetNewValue('GPSLongitude*', $data_yaml->{'Lng'});
        }

        # ALTITUDE
        # if...
        log_trace('process_file: checking if altitute set in YAML, but not in EXIF');
        if (
                #...YAML has Alt and...
                $data_yaml->{'Alt'}
                #...EXIF does NOT have GPSAltitude...
            &&  (! $data_exif->{'GPSAltitude*'})
        ) {
            # set the longitude
            log_debug('process_file: setting EXIF altitude to %s', $data_yaml->{'Alt'});
            $exif_tool->SetNewValue('GPSAltitude*', $data_yaml->{'Alt'});
        }

        # DATE
        # get DateTimeOriginal from EXIF
        log_trace('process_file: checking if EXIF has DateTimeOriginal set');
        my $date_time_exif = $data_exif->{'DateTimeOriginal'};
        log_trace('process_file: raw EXIF date_time: %s', $date_time_exif);

        # if EXIF has DateTimeOriginal...
        if ($date_time_exif) {
            # parse EXIF datetime data
            log_trace('process_file: verifying that raw EXIF date_time is properly formatted');
            $date_time_exif =~ /(\d\d\d\d):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)/;

            # verify that EXIF data received meets expected pattern
            if (
                   defined $1
                && defined $2
                && defined $3
                && defined $4
                && defined $5
                && defined $6
            ) {
                # modify parsed EXIF data if its out of bounds
                log_trace('process_file: modifying raw EXIF date_time for any out of bounds values');
                my $exif_year   = ($1 >  0 && $1 < 9999) ? $1 : '1900';
                my $exif_month  = ($2 >  0 && $2 <=  12) ? $2 :   '01';
                my $exif_day    = ($3 >  0 && $3 <=  12) ? $3 :   '01';
                my $exif_hour   = ($4 >= 0 && $4 <=  23) ? $4 :   '00';
                my $exif_minute = ($5 >= 0 && $5 <=  59) ? $5 :   '00';
                my $exif_second = ($6 >= 0 && $6 <=  59) ? $6 :   '00';

                $date_time_exif = join(':', ($exif_year, $exif_month, $exif_day)) . ' ' . join(':', ($exif_hour, $exif_minute, $exif_second));

                log_trace('process_file: final EXIF date_time: %s', $date_time_exif);

                #...convert to DateTime object
                try {
                    $date_time_exif = DateTime::Format::EXIF->parse_datetime($date_time_exif);
                } catch ($e) {
                    warn "Unable to parse DateTimeOriginal date from EXIF: ${date_time_exif} :: $e.  Setting DateTimeOriginal for YAML comparison to epoch.";

                    # ...set exif date to EPOCH
                    $date_time_exif = my $dt = DateTime->from_epoch(epoch => 0, time_zone => 'UTC');
                }
            # otherwise...
            } else {
                log_trace('process_file: raw EXIF date_time is invalid.  Setting to epoch.');
                # ...set exif date to EPOCH
                $date_time_exif = my $dt = DateTime->from_epoch(epoch => 0, time_zone => 'UTC');
            }
        # otherwise...
        } else {
            # ...set exif date to EPOCH
            log_trace('process_file: EXIF contains no datetime information.  Setting EXIF datatime information to EPOCH for comparison with YAML data');
            $date_time_exif = my $dt = DateTime->from_epoch(epoch => 0, time_zone => 'UTC');
        }
        log_debug('process_file: $date_time_exif: %s', $date_time_exif->iso8601);

        # prime/assume YAML datatime will be the same
        my $date_time_yaml = $date_time_exif->clone();

        # get the various date parts from YAML
        my $date_to_year    = $data_yaml->{'Year'}  > 0 ? $data_yaml->{'Year'}  : 1900;
        my $date_to_month   = $data_yaml->{'Month'} > 0 ? $data_yaml->{'Month'} : 1;
        my $date_to_day     = $data_yaml->{'Day'}   > 0 ? $data_yaml->{'Day'}   : 1;

        log_trace('process_file: $date_to_year: %i',  $date_to_year);
        log_trace('process_file: $date_to_month: %i', $date_to_month);
        log_trace('process_file: $date_to_day: %i',   $date_to_day);

        # ensure day is not greater than the number of days in the month!
        $date_to_day        = min($date_to_day, days_in_month($date_to_year, $date_to_month));
        log_trace('process_file: $date_to_day adjusted to: %i',   $date_to_day);

        log_trace('process_file: setting $date_time_yaml to %i-%i-%i', $date_to_year, $date_to_month, $date_to_day);
        $date_time_yaml->set(year => $date_to_year, month => $date_to_month, day => $date_to_day);
        log_trace('process_file: $date_time_yaml: %s"', $date_time_yaml->iso8601);

        # if YAML date is different than EXIF date...
        # __NOTE__ - ignoring time for YAML vs. EXIF comparison
        if (DateTime->compare($date_time_yaml->truncate(to => 'day'), $date_time_exif->truncate(to => 'day')) != 0) {
            # reset EXIF date
            log_debug('process_file: setting EXIF DateTimeOriginal to %s', $date_time_yaml->iso8601);
            $exif_tool->SetNewValue('DateTimeOriginal', $date_time_yaml->iso8601);
        }

        # If any new values have been set...
        if ($exif_tool->CountNewValues() > 0) {
            # set absolute path to original image
            my $abs_path_image_orig = $abs_path_image . '.orig';
            log_trace('process_file: $abs_path_image_orig set to "%s"', $abs_path_image_orig);

            if ($opt->{'dry_run'}) {
                say sprintf('DRY_RUN: Rename "%s" to "%s"', $abs_path_image, $abs_path_image_orig);
                my %tags;
                for my $key (keys(%{$exif_tool->{NEW_VALUE}})) {
                    $tags{$exif_tool->{NEW_VALUE}->{$key}->{'TagInfo'}->{'Name'}} = 1;
                }

                say sprintf(
                      'DRY_RUN: Write new EXIF data to "%s" for tags: %s'
                    , $abs_path_image
                    , join(', ', keys(%tags))
                );
            } else {
                # Rename original file with ".orig" extension
                log_debug('process_file: renaming "%s" to "%s"', $abs_path_image, $abs_path_image_orig);

                unless (rename($abs_path_image, $abs_path_image_orig)) {
                    # if error renaming file then log the error and return from sub-routine
                    log_error('process_file: Unable to rename "%s" to "%s" : %s', $abs_path_image, $abs_path_image_orig, $!);
                    return;
                }
                # Write the new EXIF values into a new file
                log_info('writing YAML data into EXIF for file "%s"', $abs_path_image);
                $exif_tool->WriteInfo($abs_path_image_orig, $abs_path_image);
            }
        } else {
            log_info('no new EXIF values found during processing of "%s"', $abs_path_image);
        }
    # otherwise...
    } else {
        log_info('"%s" is not a file (likely does not exist)', $abs_path_yaml);
    }
}

sub pre_process_files (@files) {
    my @paths_good;

    # loop through all the files/directories we've been handed
    log_trace('pre_process_files: pre_process_files: Checking for directories that may be skipped');
    PATH: for my $path_end (@files) {
        log_trace('pre_process_files: processing $path_end "%s"', $path_end);
        # if this is the current and parent director (. or ..)...
        if ($path_end =~ /\.{1,2}$/) {
            log_trace('pre_process_files: Skipping: "%s"', $path_end);
            next;
        }

        # if we're currently processing a directory...
        if (-d File::Spec->catfile($File::Find::dir, $path_end)) {
            # ... and this dir name is in the list of directories to ignore...
            if (exists($_skip_dirs{$path_end})) {
                # skip to the next directory entry
                log_trace('pre_process_files: Skipping directory "%s"', $path_end);
                next;
            } else {
                log_trace('pre_process_files: Adding directory "%s" to @paths_good', $path_end);
                push (@paths_good, $path_end);
            }
        # otherwise we must be looking at a file
        } else {
            # loop through all image regexes
            for my $image_regex (@_image_regexes) {
                # if  this path matches this image_regex...
                if ($path_end =~ $image_regex) {
                    # ...add this path to the list of good paths
                    log_trace('pre_process_files: Adding "%s" to items to process', $path_end);
                    push (@paths_good, $path_end);
                    # skip to the next PATH
                    next PATH;
                # otherwise...
                } else {
                    # ...log that file doesn't math @_image_regexes
                    log_trace(
                          'pre_process_files: eliminating file "%s" from processing - did not match any image regex in "%s"'
                        , $path_end
                        , join(', ', @_image_regexes)
                    );
                }
            }
        }
    }

    # return the list of good paths
    return @paths_good;
}

# Recurse through image dir
log_debug('processing image dir "%s"', $opt->{'image_dir'});
find(
      {
          preprocess => \&pre_process_files
        , wanted => \&process_file
      }
    , ($opt->{'image_dir'})
);

### Days In Month

sub days_in_month {
    my %m2d = qw(
         1      31
         3      31
         4      30
         5      31
         6      30
         7      31
         8      31
         9      30
        10      31
        11      30
        12      31
    );

    my ($year, $month) = @_;

    return $m2d{$month+0} unless $month == 2;
    return 28 unless &is_leap($year);
    return 29;

    sub is_leap
    {
            my ($year) = @_;
            return 0 unless $year % 4 == 0;
            return 1 unless $year % 100 == 0;
            return 0 unless $year % 400 == 0;
            return 1;
    }
 }

exit(0);
