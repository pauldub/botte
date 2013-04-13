import 'dart:core';
import 'dart:io';
import 'dart:async';
import 'package:irc_client/irc_client.dart';
import 'package:http/http.dart' as http;
import 'package:html5plus/parser.dart' show parse;
import 'package:dartlings/ansi_term.dart';

void log(String message) {
  var now = new DateTime.now();
  print("[${white(now)}] $message");
}

// From: https://github.com/dart-lang/web-ui-code-lab/blob/master/finished/lib/server_utils.dart
// runs the callback on the event loop at the next opportunity
Future queue(callback()) => new Future.delayed(Duration.ZERO, callback);

class LogHandler extends Handler {
  bool onChannelMessage(String channel, String from, String message, Irc irc) {
    log("${green(channel)} ${yellow(from)}: ${white(message)}");

    return false;
  }
}

class ChannelHandler extends Handler {
  String channel;

  ChannelHandler(this.channel);

  bool onConnection(Irc irc) {
    log(green("Joining $channel"));

    irc.join(channel);

    return true;
  }
}

class Link {
  String url;
  String title;
  String nick;
  DateTime postedAt;

  Link(this.url, this.nick, this.postedAt);

  String toString() => "$url (@$nick)";
}

class LinksHandler extends Handler {
  List<Link> links = [];

  bool onChannelMessage(String channel, String from, String message, Irc irc) {
    if (message.startsWith("!share ")) {
      var url   = _formatUrl(message.slice(message.indexOf(" ") + 1));
      var link  = new Link(url, from, new DateTime.now());

      _getUrlTitle(link.url)
        .then((response) {
          // TODO: Move this logic to _getUrlTitle(url)
          var exp = new RegExp(r'<title>(.*)</title>');
          var match = exp.firstMatch(response.body);

          if (!match == null && !match[0].isEmpty) {
            var title = parse(match[0]);
            link.title = title.title;

            log(link.title);
          }
        })
        .catchError((e) => print(e))
        .whenComplete(() => links.add(link));

      return true;
    } else if (message.startsWith("!linksFrom ")) {
      var nick = message.slice(message.indexOf(" ") + 1);
      irc.sendMessage(channel, _latestLinksFrom(nick));

      return true;
    } else if (message.startsWith("!links")) {
      irc.sendMessage(channel, _latestLinks());

      return true;
    }

    return false;
  }

  Future _getUrlTitle(String url) => http.get(url);

  _latestLinks() => links.reversed.take(5).join(', ');
  _latestLinksFrom(nick) => links.reversed.where((link) => link.nick == nick).take(5).join(', ');

  String _formatUrl(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = "http://$url";
    }

    return url;
  }
}

class WebSocketHandler extends Handler {
  Set<WebSocket> wsConnections = new Set<WebSocket>();

  bool onChannelMessage(String channel, String from, String message, Irc irc) {
    _broadcast("$channel $from: $message");

    return false;
  }

  _broadcast(message) => wsConnections.forEach((conn) => queue(() => conn.send(message)));

  onConnection(WebSocket conn) {
    void onMessage(message) {
      log('WebSocket: $message');
    }

    log('WebSocket: New connection');

    wsConnections.add(conn);

    conn.listen(onMessage,
      onDone: () => wsConnections.remove(conn),
      onError: (e) => wsConnections.remove(conn)
    );
  }
}

main() {
  log("Starting bot...");

  var bot = new IrcClient("botte");
  bot.realName = "Botte";

  bot.handlers.add(new ChannelHandler("#testytou245"));

  var wsHandler = new WebSocketHandler();

  bot.handlers.add(wsHandler);
  bot.handlers.add(new LogHandler());
  bot.handlers.add(new LinksHandler());

  HttpServer.bind('127.0.0.1', 3000)
    .then((HttpServer server) {
      log("WebSocket Server started on port 3000");
      server.transform(new WebSocketTransformer()).listen(wsHandler.onConnection);
    });

  bot.run("irc.freenode.net", 6667);
}
