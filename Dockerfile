# Building DateTime requires the non-slim image
FROM perl:5.41 AS build

# Install the deps from CPAN
RUN cpanm Getopt::Long::Descriptive Getopt::Simple Privileges::Drop DateTime Image::ExifTool Log::ger::Output Log::ger::Output::Screen YAML::PP DateTime::Format::EXIF List::Util

FROM perl:5.41-slim

# Copy precompiled build deps from builder image
COPY --from=build /usr/local/lib/perl5 /usr/local/lib/perl5

ADD photo_prism_yaml_to_exif.pl ./photo_prism_yaml_to_exif.pl
