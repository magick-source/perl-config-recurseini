# Config-RecurseINI

Config::RecurseINI adds two things on top of Config::Tiny:

* based on the name of the script or a parameter to first config call
  search for the config file in several places

* allow config sections to inherit from other sections

## INSTALLATION

To install this module type the following:

   perl Makefile.PL
   make
   make test
   make install

## DEPENDENCIES

This module requires these other modules and libraries:

  Config::Tiny
  Getopt::Log

## SUPPORT AND BUGS

the main issue tracking of this project is in

  http://magick-source.net/MagickPerl/Config-RecurseINI

## COPYRIGHT AND LICENCE

This is licensed with GPL 2.0+ or perl's artistic licence
the files with both licences are part of this package

Copyright (C) 2016 by theMage

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.22.1 or, 
at your option, any later version of Perl 5 you may have available.

Alternativally, you can also redistribute it and/or modify it
under the terms of the GPL 2.0 licence (or any future version of it).


