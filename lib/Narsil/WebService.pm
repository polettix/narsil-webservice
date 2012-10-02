package Narsil::WebService;
use 5.012;
use English qw< -no_match_vars >;
use Dancer ':syntax';
use Dancer::Plugin::FlashNote qw< flash >;
use Try::Tiny;

get '/' => sub {
   return {here => 'I am', %{scalar config()}};
};

sub require_package {
   state $local_INC;
   if (! $local_INC) {
      require lib; # use lib... together with following line
      lib->import(@{config()->{narsil}{local_INC} // []});
      $local_INC = 1;
   }
   for my $package (@_) {
      (my $path = $package . '.pm') =~ s{(?: :: | ')}{/}gmxs;
      require $path;
   }
}

sub model {
   state $model;
   if (!$model) {
      my $config = config()->{narsil}; # application-specific configs

      # get class for model
      my $mclass = $config->{'model'} // 'Narsil::Model::Memory';
      warning "using model class $mclass";
      require_package($mclass);

      # get data to initialize it, it can be overridden
      my $connector = $config->{connector} // {};
      my $parameters = $connector->{parameters};
      if (defined(my $pclass = $connector->{class})) {
         warning "shaping parameters via class $pclass";
         require_package($pclass);
         $parameters = $pclass->parameters($parameters, $mclass);
      }

      warning "using parameters " . to_json($parameters);
      $model = $mclass->create($parameters);
   } ## end if (!$model)
   return $model;
} ## end sub model

sub _response {
   my ($code, $headers, $body) = @_;
   status $code;
   headers @$headers if defined $headers;
   return $body // '';
} ## end sub _response

sub _get_match {
   my $id = shift // param('id');
   my $match = model()->get_match($id);

   # Perform checks against user() if necessary
   return $match;
} ## end sub _get_match

sub _rh_errorchecked {
   my ($sub, @params) = @_;
   my ($retval, $error);
   try { $retval = $sub->(@params) or die {} }
   catch { warning "catched: $_" ; send_error('Not Found', 404) };
   return $retval;
} ## end sub _rh_errorchecked

sub _rh_get_match {    # to be called INSIDE route handlers
   return _rh_errorchecked(\&_get_match, @_);
}

sub _path_id {
   my $type   = shift;
   my @retval = map {
      my $id = ref $_ ? $_->id() : $_;
      "/$type/$id";
   } @_;
   return @retval if wantarray();
   return $retval[0];
} ## end sub _path_id

sub _uri_id {
   my $request = request();
   my @retval = map { $request->uri_for($_)->as_string() } _path_id(@_);
   return @retval if wantarray();
   return $retval[0];
}

sub _internal_id {
   my $expected_type = shift;
   my @retval        = map {
      my ($type, $id) = m{/ ([^/]+) / ([^/]+)\z}mxs
        or die {reason => "uri $_ is not identifiable"};
      die {reason => "no id of type $expected_type (got $type from $_)"}
        if defined($expected_type) && $expected_type ne $type;
      $expected_type ? $id : [$type, $id];
   } @_;
   return @retval if wantarray();
   return $retval[0];
} ## end sub _internal_id

=head1 AUTHENTICATION


=cut

sub login_path { return '/login' }
sub logout_path { return '/logout' }

hook before => sub {
   #request->path_info('/unauthorized') unless is_authorized();
   return;
};

any [qw< get post >] => '/unauthorized' => sub {
   send_error('Unauthorized', 401);
};

any [qw< get post >] => '/forbidden' => sub {
   send_error('Forbidden', 403);
};

sub is_authorized {
   my $request = request();
   return 1 if $request->path_info() eq login_path() || $request->is_get() || $request->is_head() || session('user');
   return ;
}

post login_path() => sub {
   my $username = param('username');
   my $password = param('password');
   my $user = model()->get_user($username);
   # use bcrypt or whatever, then...
   warning "checking $password against " . $user->password();
   send_error('Not allowed', 403) unless $user && $user->password() eq $password;
   #session user => $username;
   return { message => 'authenticated' };
};

post logout_path () => sub {
   session user => undef;
   return { message => 'logged out' };
};

sub user {
   return param('user');
   return session 'user';
}


=head1 DATA STRUCTURES

All data structures are transferred using JSON encoding.

=head2 Match

A Match represents the data available for a match.

The following elements can be present depending on the request (a
request for the whole Match object will contain them all, a specialized
request --e.g. GetStatus-- will contain only those marked as I<Always present>
or the specific element requested):

=over

=item B<< uri >>

the match identifier/endpoint URI.

Always present

=item B<< game >>

the URI of the game this match complies to.

Always present

=item B<< phase >>

the match phase. The following values are possible:

=over

=item pending

a request to create the match is inserted in the system but still pending
approval

=item rejected

the request for the match has been rejected

=item gathering

the match is accepted and waiting for all participants to join

=item active

the match is accepted and ongoing

=item terminated

the match is accepted and terminated

=back

Always present.

=item B<< configuration >>

the match configuration. Its format is game specific and thus it is
considered an opaque string of data.

It is present in a request for the overall match object; in case of
specialised requests, it will be present only in a request specific
for this field.

=item B<< status >>

the match status. Its format is game specific and thus it is considered
an opaque string of data. This field is present only if the match
is accepted.

It is present in a request for the overall match object; in case of
specialised requests, it will be present only in a request specific
for this field.


=item B<< participants >>

the list of participants in an array containing URIs of user endpoints.
This field is present only if the match is accepted.

It is present in a request for the overall match object; in case of
specialised requests, it will be present only in a request specific
for this field.


=item B<< invited >>

the list of invited users in an array containing URIs of user endpoints.
This field is present only if the match is accepted.

It is present in a request for the overall match object; in case of
specialised requests, it will be present only in a request specific
for this field.


=item B<< movers >>

the list of users allowed to make a move in an array containing URIs
of user endpoints. This field is present only if the match is accepted.

It is present in a request for the overall match object; in case of
specialised requests, it will be present only in a request specific
for this field.


=item B<< winners >>

the list of winners in an array containing URIs of user endpoints.
This field is present only if the match is accepted.

It is present in a request for the overall match object; in case of
specialised requests, it will be present only in a request specific
for this field.


=item B<< joins >>

the list of join attempts in an array containing URIs for join
endpoints. This field is present only if the match is accepted.

It is present in a request for the overall match object; in case of
specialised requests, it will be present only in a request specific
for this field.


=item B<< moves >>

the list of moves in an array containing URIs for move endpoints. This
field is present only if the match is accepted.

It is present in a request for the overall match object; in case of
specialised requests, it will be present only in a request specific
for this field.


=item B<< endpoints >>

the endpoints (URIs) to use for fetching selected data on the match without
getting them all together or to perform operations on the match.

The endpoints are provided only for accepted matches, see I<phase> above.

The following endpoints are available:

=over

=item configuration

for fetching the match configuration only (this should be overkill because
the configuration is returned in the match structure and will not change).

=item status

for fetching the match status only, which is the only part likely to change
when the match is ongoing (thus getting it only will save bandwidth).

=item participants

for fetching the list of participants only (see above) or for requesting
to participate

=item invited

for fetching the list of invited users only (see above)

=item movers

for fetching the list of users allowed to make a move (see above)

=item winners

for fetching the list of winner users only (see above)

=item joins

for fetching the list of joins only (see above) or to request to join
the match (which is an attempt to modify the participants, by the way).

=item moves

for fetching the list of moves only (see above) or to make moves (which are
also attempts to modify the status, by the way).

=back

It is present in a request for the overall match object; in case of
specialised requests, it will be present only in a request specific
for this field.

=back

In addition to the above requested subobjects, there are also the following
meta-options that can be requested:


=over

=item B<< :all >>

This is equivalent to not requesting any particular feature, i.e. leave the
input arguments list empty. It is provided for completeness and to allow
specifying other meta-options (e.g. L</:game> below).

=item B<< :game >>

Provide a full dump of the relevant game object instead of the simple game
URI identifier.

=back

=cut

sub _flagify {
   map { $_ => 1 } @_;
}

sub _id_uri_list {
   my $type = shift;
   map { [$_ => _uri_id($type => $_)] } @_;
}

sub _userlist {
   map { [$_ => _uri_id(user => $_)] } @_;
}

sub _serializable_match {
   my $match        = shift;
   my %is_requested = _flagify(@_);
   my $all          = !scalar(@_) || $is_requested{':all'};

   # Basic stuff, always present
   my %match = (
      uri   => _uri_id(match => $match),
      game  => _uri_id(game  => $match->gameid()),
      phase => $match->phase(),
      creator => $match->creator(),
   );

   $match{game} = $is_requested{':game'} ? _serializable_game($match->game()) : $match->gameid();

   $match{configuration} = $match->configuration()
     if $all || $is_requested{configuration};

   my %is_accepted = _flagify(qw< gathering active terminated >);
   if ($is_accepted{$match{phase}}) {
      warning "user: " . (user() // '*undef*');
      $match{status} = $match->status_for(user())
        if $all || $is_requested{status};
      $match{participants} = [_userlist($match->participants())]
        if $all || $is_requested{participants};
      $match{invited} = [_userlist($match->invited())]
        if $all || $is_requested{invited};
      $match{movers} = [_userlist($match->movers())]
        if $all || $is_requested{movers};
      $match{winners} = [_userlist($match->winners())]
        if $all || $is_requested{winners};
      $match{joins} = [_uri_id(join => $match->join_ids())]
        if $all || $is_requested{joins};
      $match{moves} = [_uri_id(move => $match->move_ids())]
        if $all || $is_requested{moves};

      if ($all || $is_requested{endpoints}) {
         my $id = $match->id();
         $match{endpoints} = {
            map { $_ => _uri_id("/match/$_" => $id) }
              qw<
              configuration
              status
              participants
              invited
              movers
              winners
              joins
              moves
              >
         };
      } ## end if ($all || $is_requested...
   } ## end if ($is_accepted{$match...
   return \%match;
} ## end sub _serializable_match

=head2 Join Request

A I<Join Request> represents a request of a user to join a match.

The following elements are present:

=over

=item B<< uri >>

the request identifier/URI endpoint

=item B<< match >>

the identifier of the match (URI of the match endpoint)

=item B<< phase >>

the phase of the request, with the following possible values:

=over

=item pending

the request has been recorded but it is still pending approval

=item rejected

the request to join the match has been refused (e.g. the user is not
allowed to join the match)

=item accepted

the request has been accepted

=back

=item B<< message >>

a reason why the request has been accepted or rejected, if any

=back

=cut

sub _serializable_join {
   my ($join) = @_;
   return {
      uri     => _uri_id(join  => $join),
      match   => _uri_id(match => $join->matchid()),
      phase   => $join->phase(),
      message => $join->message(),
   };
} ## end sub _serializable_join

=head2 Move

A Move represents a request to perform a move in a Match.

The following elements are present:

=over

=item B<< uri >>

the move id/endpoint URI

=item B<< phase >>

the move (acceptance) phase, which can be one of the following:

=over

=item pending

the request to make the move is in the system but has to be processed

=item rejected

the move has been processed and rejected (the message field should
hopefully provide a reason depending on the game)

=item accepted

the move has been processed and accepted

=back

=item B<< message >>

a message associated to the move, e.g. the reason for rejection

=item B<< match >>

information about the match related to the move, with the following
fields:

=over

=item uri

the match endpoint URI

=item status

the different statuses of the match associated to the move. This part is
present only if the move has been processed, i.e. if its status is
not C<pending> (see above).

In particular:

=over

=item before

the status of the match (see L</Match>) as it was when the move
was issued

=item after

the status of the match (see L</Match>) as it was after the
application of the move. This field is present only if the move has been
processed and accepted, see above for the possible statuses of the move
request.

=back

=back

=back

=cut

sub _serializable_move {
   my ($move)          = @_;
   my $move_phase      = $move->phase();
   my $requesting_user = user();
   my %move            = (
      uri   => _uri_id(move => $move),
      phase => $move_phase,
      match   => {uri         => _uri_id(match => $move->matchid()),},
      user    => _uri_id(user => $move->userid()),
      message => $move->message(),
   );
   $move{contents} = $move->contents_for($requesting_user);
   if ($move_phase ne 'pending') {
      $move{match}{before} = {
         status => $move->match_status_before_for($requesting_user),
         phase  => $move->match_phase_before(),
      };
   } ## end if ($move_phase ne 'pending')
   if ($move_phase eq 'accepted') {
      $move{match}{after} = {
         status => $move->match_status_after_for($requesting_user),
         phase  => $move->match_phase_after(),
      };
   } ## end if ($move_phase eq 'accepted')
   return \%move;
} ## end sub _serializable_move


=head2 Game


=cut

sub _serializable_game {
   my ($game)          = @_;
   return { 
      uri   => _uri_id(game => $game),
      %{_serializable_game($game)},
   };
} ## end sub _serializable_move



=head1 METHODS

The following methods have indicative names but you have to refer to the
actual HTTP Method and to the provided Endpoints. Endpoints indicated
with a star (i.e. marked as "Endpoint*") are examples and you should
find the right endpoint in the relevant data structure indicated in the
textual comment.

=head2 CreateMatch

   Endpoint: /match
   Method:   POST

Create a new match. Input:

=over

=item B<< game >>

mandatory, URI of the game the new match should comply to

=item B<< configuration >>

optional configuration (specific to game)

=back

If match is successfully created it is returned, see L</Match> for
details.

=cut

post '/match' => sub {
   my $match;
   try {
      my $model = model();
      use YAML;
      my $method        = $model->can('create_match');
      my $user          = user();
      my $gameuri       = param('game');
      my $gameid        = _internal_id(game => $gameuri);
      my $configuration = param('configuration');
      warning "creating match with configuration $configuration";
      $match = $model->create_match(
         creator       => $user,
         gameid        => $gameid,
         configuration => $configuration,
      ) or die {};
   } ## end try
   catch {
      warning "caught: $_ - " . YAML::Dump($_);
      send_error('Internal Server Error', 500);
   };
   my $smatch = _serializable_match($match);
   return _response('Created', [Location => $smatch->{uri}], $smatch);
};

=head2 B<< GetMatch >>

   Endpoint*: /match/:id
   Method:    GET

Does not take input parameters.

See L</Match> for details on getting the endpoint.

Returns the main match data according to what described in L</Match>.

=cut

get '/match/:id' => sub {
   return _serializable_match(_rh_get_match(param('id')));
};

=head2 GetMatchConfiguration

   Endpoint*: <specified in match>
   Method:   GET

Get the configuration set for the match. See L</Match> for details.

See L</Match> for details on getting the endpoint.

=cut

get '/match/configuration/:id' => sub {
   return _serializable_match(_rh_get_match(param('id')), 'configuration');
};

=head2 GetMatchStatus

   Endpoint*: /match/status/:id
   Method:    GET

Get the status for the match, whatever this means. See L</Match> for
further details.

See L</Match> for details on getting the endpoint.

=cut

get '/match/status/:id' => sub {
   return _serializable_match(_rh_get_match(param('id')), 'status');
};

=head2 GetMatchParticipants

   Endpoint*: /match/participants/:id
   Method:    GET

Get the list of participants currently participating in the match.

See L</Match> for details on getting the endpoint.

=cut

get '/match/participants/:id' => sub {
   return _serializable_match(_rh_get_match(param('id')), 'participants');
};

=head2 GetMatchInvited

   Endpoint*: /match/invited/:id
   Method:    GET

Get the list of participants currently invited to the match. This list
is used to pre-filter participation requests, but the final participation
decision is taken only when trying to join a match.

See L</Match> for details on getting the endpoint.

=cut

get '/match/invited/:id' => sub {
   return _serializable_match(_rh_get_match(param('id')), 'invited');
};


=head2 GetMatchWinners

   Endpoint*: /match/winners/:id
   Method:    GET

Get the list of winners of the match.

See L</Match> for details on getting the endpoint.

=cut

get '/match/winners/:id' => sub {
   return _serializable_match(_rh_get_match(param('id')), 'winners');
};

=head2 GetJoins

   Endpoint*: /match/joins/:id
   Method:    GET

Get the list of joins for the match, provided as a list (array) of
URI endpoints.

See L</Match> for details on getting the endpoint.

=cut

get '/match/joins/:id' => sub {
   return _serializable_match(_rh_get_match(param('id')), 'joins');
};

=head2 MatchJoin

   Endpoint*: /match/joins/:id
   Method:    POST

Request to join the match, i.e. to participate to the match.

See L</Match> for details on getting the endpoint. In particular, you
have to use the endpoint associated to C<joins>.

=cut

post '/match/joins/:id' => sub {
   my $match = _rh_get_match();
   my $join;
   try { $join = $match->join(user()); }
   catch {
      warning "caught: $_ - " . YAML::Dump($_);
      send_error('Internal Server Error', 500);
   };
   my $sjoin = _serializable_join($join);
   return _response('Created', [Location => $sjoin->{uri}], $sjoin);
};

=head2 GetJoin

   Endpoint*: /join/:id
   Method:    GET

The endpoint is available in the result to a L</MatchJoin> or can be
gathered through the L</Match> facilities.

=cut

get '/join/:joinid' => sub {

   # my $match = _rh_get_match(param('matchid'));
   my $join =
     _rh_errorchecked(sub { model()->get_join(@_) }, param('joinid'));
   return _serializable_join($join);
};

=head2 GetMoves

   Endpoint*: /match/moves/:id
   Method:    GET

Get the list of moves for the match, provided as a list (array) of
URI endpoints.

See L</Match> for details on getting the endpoint.

=cut

get 'match/moves/:id' => sub {
   return _serializable_match(_rh_get_match(param('id')), 'moves');
};

=head2 MatchMove

   Endpoint*: /match/moves/:id
   Method:  POST

Attempts to make a move on the match.

The input parameter C<move> contains the requested move. Its format is
specific to the game and is considered opaque data.

See L</Match> for details on getting the endpoint; in particular, you have
to use the endpoint for C<moves>.

See L</Move> for details on the returned data.

=cut

post '/match/moves/:id' => sub {
   my $match = _rh_get_match();
   my $move;
   try { $move = $match->move(user(), param('move')); }
   catch {
      warning "caught: $_ - " . YAML::Dump($_);
      send_error('Internal Server Error', 500);
   };
   my $smove = _serializable_move($move);
   return _response('Created', [Location => $smove->{uri}], $smove);
};

=head2 GetMove

   Endpoint*: /move/:moveid
   Method:    GET

The endpoint is available in the result to a L</MatchMove> or can be
gathered through the L</Match> facilities.

=cut

get '/move/:moveid' => sub {
   my $move =
     _rh_errorchecked(sub { model()->get_move(@_) }, param('moveid'),);
   return _serializable_move($move);
};

get '/matches/gathering' => sub {
   my $model = model();
   my @matches = map {
      my $match = $model->get_match($_);
      my $retval = _serializable_match($match, 'participants' );
      $retval->{game} = {
         uri => $retval->{game},
         name => $match->game()->name(),
      };
      $retval;
   } $model->matches_id_for('gathering');
   return { phase => 'gathering', matches => \@matches };
};

get '/user/matches/:id' => sub {
   my $phase = param('phase') // 'active';
   my $userid = param('id');
   warning "\n getting $phase for $userid \n";
   my $model = model();
   my @matches = map {
      my $match = $model->get_match($_);
      my $retval = _serializable_match($match, 'participants', 'movers' );
      $retval->{game} = {
         uri => $retval->{game},
         name => $match->game()->name(),
      };
      $retval;
   } $model->matches_id_for($phase, $userid);
   return {
      id => _uri_id(user => $userid),
      matches => \@matches,
   };
};

get '/game/:id' => sub {
   my $id = param('id');
   my $game = model()->get(game => $id);
   return $game->plain();
};

get '/games' => sub {
   return [
      map { scalar $_->plain() } model()->games()
   ];
};

sub _serializable_user {
   my ($user) = @_;
   return {
      id => $user->id(),
      uri => _uri_id(user => $user->id()),
   };
}

get '/users' => sub {
   return [ map { _serializable_user($_) } model()->users() ];
};

true;

__END__
