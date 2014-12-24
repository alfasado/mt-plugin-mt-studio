#!/usr/bin/perl -w

use strict;
use lib $ENV{MT_HOME}
    ? "$ENV{MT_HOME}/plugins/Developer/lib"
    : 'plugins/Developer/lib';
use lib $ENV{MT_HOME}
    ? "$ENV{MT_HOME}/plugins/Developer/lib"
    : 'addons/plugins/Developer';
use lib $ENV{MT_HOME} ? "$ENV{MT_HOME}/lib" : 'lib';
use MT::Bootstrap App => 'MT::App::Developer';
