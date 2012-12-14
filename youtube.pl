#!/usr/bin/perl
# YouTube for Irssi by Amanda Folson
# Based on youtube-title by Olof "zibri" Johansson <olof@ethup.se> https://github.com/olof/irssi-youtube-title
# and
# Automatic YouTube by Louis T. http://ltdev.im/

# TODO:
# Clean up source
use strict;
use Irssi;
use WWW::Mechanize;
use JSON -support_by_pp;
use Time::Duration;
use Class::Date qw(:errors date -EnvC);
use Number::Format qw(:subs :vars);



use HTML::Entities;
use URI;
use URI::QueryParam;
use Regexp::Common qw/URI/;

my $VERSION = '0.1';

my %IRSSI = (
	authors		=> 'Amanda Folson',
	contact		=> 'amanda.folson@gmail.com',
	name		=> 'youtube-preview',
	uri			=> 'https://github.com/afolson/youtube-preview',
	description	=> 'prints the title of a youtube video automatically',
	license		=> 'WTFPL',
);

# If a YouTube link is seen, display the data. Default to ON.
Irssi::settings_add_bool('youtube', 'yt_print_links', 1);
# If you submit a link, display the data. Default to OFF.
Irssi::settings_add_bool('youtube', 'yt_print_own_links', 0);

# Look for YouTube links in messages sent to us
sub callback {
	my($server, $msg, $nick, $address, $target) = @_;
	$target=$nick if $target eq undef;
	if(Irssi::settings_get_bool('yt_print_links')) {
			# A wild YouTube link appears! Irssi used PARSE. It's super effective!
			process($server, $target, $_) for (getID($msg));
	}
}

# Look for YouTube links in messages sent from us
sub own_callback {
	my($server, $msg, $target) = @_;
	if(Irssi::settings_get_bool('yt_print_own_links')) {
		callback($server, $msg, undef, undef, $target);
	}
}

sub process {
	my ($server, $target, $id) = @_;
	my $yt = getInfo($id);	
	if(exists $yt->{error}) {
		print_error($server, $target, $yt->{error});
	}
	else {
		printInfo($server, $target, $yt->{title}, $yt->{duration}, $yt->{views}, $yt->{rating}, $yt->{raters}, $yt->{likes}, $yt->{dislikes}, $yt->{author}, $yt->{date});
	}
}

sub print_error {
	my ($server, $target, $msg) = @_;
	$server->window_item_find($target)->printformat(MSGLEVEL_CLIENTCRAP, 'yt_error', $msg);
}
sub getID {

	my $string = shift;
	if ($string =~ m/(?:https?:\/\/)?(?:www.)?youtu(?:\.be\/|be\.com\/(?:watch\?.*?v=)?)([^\?#&\s]+)/i) {
		return $1;
	}
	else {
		return 0;
	}
}
sub printInfo {
	my ($server, $target, $title, $duration, $views, $rating, $raters, $likes, $dislikes, $author, $date) = @_;
	my $item;
	
	foreach $item (@_) {
		decode_entities($item);
	} 
# 	$title = decode_entities($title);
# 	$duration = decode_entities($duration);
# 	$views = decode_entities($views);
# 	$rating = decode_entities($rating);
# 	$raters = decode_entities($raters);
# 	$likes = decode_entities($likes);
# 	$dislikes = decode_entities($dislikes);
# 	$author = decode_entities($author);
# 	$date = decode_entities($date);
	$server->window_item_find($target)->printformat(MSGLEVEL_CLIENTCRAP, 'youtube_info', $title, $duration, $views, $rating, $raters, $likes, $dislikes, $author, $date);
}

sub getInfo {
	my($vid)=@_;
	my $url = "http://gdata.youtube.com/feeds/api/videos/$vid?v=2&alt=json";

	my $browser = WWW::Mechanize->new();
	eval {
		$browser->get($url);
	};
	if ($@) {
		return 0;
	};

	my $title;
	my $duration;
	my $views;
	my $rating;
	my $raters;
	my $likes;
	my $dislikes;
	my $author;
	my $date;
	
	if ($browser->status() eq 200) {
		my $json = new JSON;
		my $jsonResp = $json->allow_nonref->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($browser->content());
		
		if ($jsonResp->{'entry'}) {
			my $data = $jsonResp->{'entry'};

			if ($data->{'title'}->{'$t'}) {
				$title = $data->{'title'}->{'$t'};
				
				if ($data->{'media$group'}->{'yt$duration'}->{'seconds'}) {
					$duration = duration($data->{'media$group'}->{'yt$duration'}->{'seconds'});
				}
				
				if ($data->{'yt$statistics'}->{'viewCount'}) {
					$views = format_number($data->{'yt$statistics'}->{'viewCount'});
				}
				
				if ($data->{'gd$rating'}->{'average'}) {
					$rating = format_number($data->{'gd$rating'}->{'average'});
					if ($data->{'gd$rating'}->{'numRaters'}) {
						$raters = format_number($data->{'gd$rating'}->{'numRaters'});
					}
					
					if ($data->{'yt$rating'}->{'numLikes'}) {
						$likes = format_number($data->{'yt$rating'}->{'numLikes'});
						
						if ($data->{'yt$rating'}->{'numDislikes'}) {
							$dislikes = format_number($data->{'yt$rating'}->{'numDislikes'});
						}
					}
				}
				
				if ($data->{'author'}->[0]->{'name'}->{'$t'}) {
					$author = $data->{'author'}->[0]->{'name'}->{'$t'};
					if ($data->{'published'}->{'$t'}) {
						$date = date($data->{'published'}->{'$t'});
						# ?
						$Class::Date::DATE_FORMAT=undef;
					}
				}
			}
			if($title) {
				return {
					title => $title,
					duration => $duration,
					views => $views,
					rating => $rating,
					raters => $raters,
					likes => $likes,
					dislikes => $dislikes,
					author => $author,
					date => $date,	
				};
			}
		}
		else {
			return {error => 'Unable to find entry.'};
		}
	}
	else {
		return {error => 'Error IRL.'};
	}
}

Irssi::theme_register([
	'youtube_info', '%yYouTube:%n Title: $0 - Duration: $1 - Views: $2 - Rating: $3 (%g$4%n/%r$5%n) Favorites: $6 by $7 ($8)',
	'yt_error', '%rError fetching youtube title:%n $0',
]);


# Oh lawd is dat sum CALLBACK
Irssi::signal_add("message public", \&callback);
Irssi::signal_add("message private", \&callback);

Irssi::signal_add("message own_public", \&own_callback);
Irssi::signal_add("message own_private", \&own_callback);
