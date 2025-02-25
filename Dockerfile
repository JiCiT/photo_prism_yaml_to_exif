# syntax=docker/dockerfile:1

# Stage 1: full perl
FROM perl:5.41 AS build

# install the deps from CPAN
RUN cpanm \
    Specio::Library::String \
    Getopt::Long::Descriptive \
    Getopt::Simple \
    Privileges::Drop \
    DateTime \
    Image::ExifTool \
    Log::ger::Output \
    Log::ger::Output::Screen \
    YAML::PP \
    DateTime::Format::EXIF \
    DateTime::Format::ISO8601 \
    List::Util

# patch Descriptive.pm
COPY ./Descriptive.pm_2.55_datatypes.patch ./
RUN patch /usr/local/lib/perl5/site_perl/5.41.*/Getopt/Long/Descriptive.pm ./Descriptive.pm_2.55_datatypes.patch

# Stage 2: slim perl
FROM perl:5.41-slim

# Copy precompiled build deps from builder image
COPY --from=build /usr/local/lib/perl5 /usr/local/lib/perl5

# Copy the executable from source
COPY photo_prism_yaml_to_exif.pl /usr/src/photo_prism_yaml_to_exif/

WORKDIR /usr/src/photo_prism_yaml_to_exif

ENTRYPOINT ["perl", "./photo_prism_yaml_to_exif.pl"]