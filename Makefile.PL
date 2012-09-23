
use strict;
use warnings;

use 5.012_000;

use ExtUtils::MakeMaker 6.30;

my %WriteMakefileArgs = (
   "ABSTRACT"           => "A webservice for the Narsil system",
   "AUTHOR"             => "Flavio Poletti <polettix\@cpan.org>",
   "BUILD_REQUIRES"     => {},
   "CONFIGURE_REQUIRES" => {"ExtUtils::MakeMaker" => "6.30"},
   "DISTNAME"           => "Narsil-WebService",
   "EXE_FILES"          => ["bin/app.pl"],
   "LICENSE"            => "artistic_2",
   "NAME"               => "Narsil::WebService",
   "PREREQ_PM"          => {
      'Test::More'                => 0,
      'YAML'                      => 0,
      'Dancer'                    => 0,
      'Dancer::Plugin::FlashNote' => 0,
      'DotCloud::Environment'     => '0.9.2',
      'Plack::Request'            => 0,
      'Template'                  => 0,
      'JSON'                      => 0,
      'Redis'                     => 0,
      'Path::Class'               => 0,
      'Digest::MD5'               => 0,
      'LWP::UserAgent'            => 0,
   },
   "VERSION" => "0.1.0",
   "test"    => {"TESTS" => "t/*.t"}
);

unless (eval { ExtUtils::MakeMaker->VERSION(6.56) }) {
   my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
   my $pp = $WriteMakefileArgs{PREREQ_PM};
   for my $mod (keys %$br) {
      if (exists $pp->{$mod}) {
         $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
      }
      else {
         $pp->{$mod} = $br->{$mod};
      }
   } ## end for my $mod (keys %$br)
} ## end unless (eval { ExtUtils::MakeMaker...

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);

