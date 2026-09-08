import 'package:atrium/src/dashboard/widgets/downloads_widget.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_qbittorrent/service_qbittorrent.dart';

import 'dashboard_widgets_test.dart' show makeInstance, pumpBody;

/// What is moving has to outrank what is waiting.
///
/// Issue #144 follow-up: the card shows three rows and sorted purely on
/// progress, so a queue full of nearly-complete torrents pushed the one
/// actually downloading off the bottom. Someone with a busy queue saw a card
/// called "Active downloads" that never showed the active download.
void main() {
  testWidgets('a live download outranks queued ones sitting at more progress',
      (WidgetTester tester) async {
    final Instance qbit = makeInstance(ServiceKind.qbittorrent);

    await pumpBody(
      tester,
      <Override>[
        qbitRawTorrentsProvider(qbit).overrideWith(
          (Ref ref) async => const <QbitTorrent>[
            // Three queued and nearly done. On progress alone these take every
            // slot on the card.
            QbitTorrent(
              hash: 'q1',
              name: 'Queued A',
              state: 'queuedDL',
              progress: 0.98,
            ),
            QbitTorrent(
              hash: 'q2',
              name: 'Queued B',
              state: 'queuedDL',
              progress: 0.97,
            ),
            QbitTorrent(
              hash: 'q3',
              name: 'Queued C',
              state: 'queuedDL',
              progress: 0.96,
            ),
            // Barely started, but it is the one actually running.
            QbitTorrent(
              hash: 'd1',
              name: 'Actually Downloading',
              state: 'downloading',
              progress: 0.04,
              dlspeed: 1048576,
            ),
          ],
        ),
        qbitTransferProvider(qbit).overrideWith(
          (Ref ref) async => const QbitTransferInfo(dlSpeed: 1048576),
        ),
      ],
      DashboardDownloadsWidget(
        qbitInstances: <Instance>[qbit],
        sabInstances: const <Instance>[],
        nzbgetInstances: const <Instance>[],
        delugeInstances: const <Instance>[],
        transmissionInstances: const <Instance>[],
        rtorrentInstances: const <Instance>[],
      ),
    );

    expect(
      find.text('Actually Downloading'),
      findsOneWidget,
      reason: 'the only moving download must make the card, whatever its '
          'progress next to a queue of nearly-complete torrents',
    );
    // Only three rows fit, so the lowest-progress queued one gives up its slot
    // rather than the live download.
    expect(find.text('Queued C'), findsNothing);
  });

  testWidgets('a stalled download ranks below a moving one',
      (WidgetTester tester) async {
    // Stalled means connected to nobody. It is still a download someone is
    // waiting on, so it stays counted and visible, just not ahead of one that
    // is actually transferring.
    final Instance qbit = makeInstance(ServiceKind.qbittorrent);

    await pumpBody(
      tester,
      <Override>[
        qbitRawTorrentsProvider(qbit).overrideWith(
          (Ref ref) async => const <QbitTorrent>[
            QbitTorrent(
              hash: 's1',
              name: 'Stalled One',
              state: 'stalledDL',
              progress: 0.9,
            ),
            QbitTorrent(
              hash: 'd1',
              name: 'Moving One',
              state: 'downloading',
              progress: 0.1,
            ),
          ],
        ),
        qbitTransferProvider(qbit).overrideWith(
          (Ref ref) async => const QbitTransferInfo(),
        ),
      ],
      DashboardDownloadsWidget(
        qbitInstances: <Instance>[qbit],
        sabInstances: const <Instance>[],
        nzbgetInstances: const <Instance>[],
        delugeInstances: const <Instance>[],
        transmissionInstances: const <Instance>[],
        rtorrentInstances: const <Instance>[],
      ),
    );

    final Offset moving = tester.getTopLeft(find.text('Moving One'));
    final Offset stalled = tester.getTopLeft(find.text('Stalled One'));
    expect(moving.dy, lessThan(stalled.dy));
  });

  testWidgets('queued still counts, it is only ranked lower',
      (WidgetTester tester) async {
    // Dropping queued from the count would understate how much is on the go,
    // which is not what was asked for.
    final Instance qbit = makeInstance(ServiceKind.qbittorrent);

    await pumpBody(
      tester,
      <Override>[
        qbitRawTorrentsProvider(qbit).overrideWith(
          (Ref ref) async => const <QbitTorrent>[
            QbitTorrent(
              hash: 'q1',
              name: 'Queued A',
              state: 'queuedDL',
              progress: 0.5,
            ),
            QbitTorrent(
              hash: 'd1',
              name: 'Moving One',
              state: 'downloading',
              progress: 0.2,
            ),
          ],
        ),
        qbitTransferProvider(qbit).overrideWith(
          (Ref ref) async => const QbitTransferInfo(),
        ),
      ],
      DashboardDownloadsWidget(
        qbitInstances: <Instance>[qbit],
        sabInstances: const <Instance>[],
        nzbgetInstances: const <Instance>[],
        delugeInstances: const <Instance>[],
        transmissionInstances: const <Instance>[],
        rtorrentInstances: const <Instance>[],
      ),
    );

    expect(find.text('Queued A'), findsOneWidget);
    expect(find.text('Moving One'), findsOneWidget);
  });
}
