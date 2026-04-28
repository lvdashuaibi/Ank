import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'card_dsl_import_screen.dart';
import 'editor/card_editor_screen.dart';
import 'screens.dart';

final GoRouter appRouter = GoRouter(
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder:
          (
            BuildContext context,
            GoRouterState state,
            StatefulNavigationShell navigationShell,
          ) {
            return AppShellScreen(
              navigationShell: navigationShell,
              location: state.uri.path,
            );
          },
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (context, state) => const DeckListScreen(),
              routes: <RouteBase>[
                GoRoute(
                  path: 'deck/:deckId',
                  builder: (context, state) =>
                      DeckDetailScreen(deckId: state.pathParameters['deckId']!),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'add-card',
                      builder: (context, state) => BlockCardEditorScreen(
                        deckId: state.pathParameters['deckId']!,
                      ),
                    ),
                    GoRoute(
                      path: 'card/:cardId/edit',
                      builder: (context, state) => BlockCardEditorScreen(
                        deckId: state.pathParameters['deckId']!,
                        cardId: state.pathParameters['cardId'],
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'import/dsl',
                  builder: (context, state) => const CardDslImportScreen(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/review',
              builder: (context, state) =>
                  ReviewScreen(deckId: state.uri.queryParameters['deck_id']),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/stats',
              builder: (context, state) => const StatsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
