import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import 'models.dart';
import 'repository.dart';

/// Shared server-state providers used across features (the TanStack Query
/// equivalents of the web's useOrgs / useProjects / useUnreadCount hooks).
/// Feature-specific providers live next to their screens.

final orgsProvider =
    FutureProvider.autoDispose<List<Organization>>((ref) async {
  ref.watch(authProvider.select((s) => s.status));
  return ref.watch(repositoryProvider).orgs();
});

/// The active org: the persisted selection if still valid, else the first.
final activeOrgProvider =
    Provider.autoDispose<AsyncValue<Organization?>>((ref) {
  final selected = ref.watch(currentOrgProvider);
  return ref.watch(orgsProvider).whenData((orgs) {
    if (orgs.isEmpty) return null;
    return orgs.firstWhere((o) => o.slug == selected, orElse: () => orgs.first);
  });
});

final orgDetailProvider =
    FutureProvider.autoDispose.family<Organization, String>(
  (ref, slug) => ref.watch(repositoryProvider).org(slug),
);

final membersProvider = FutureProvider.autoDispose.family<List<Member>, String>(
  (ref, slug) => ref.watch(repositoryProvider).members(slug),
);

final projectsProvider =
    FutureProvider.autoDispose.family<List<Project>, String>(
  (ref, slug) => ref.watch(repositoryProvider).projects(slug),
);

final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(authProvider.select((s) => s.status));
  return ref.watch(repositoryProvider).unreadCount();
});
