import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/teacher_view_model.dart';
import 'components.dart';
import 'mobile_theme.dart';
import 'screens.dart';

class TeacherMobileApp extends StatefulWidget {
  const TeacherMobileApp({super.key, required this.model});
  final TeacherViewModel model;
  @override
  State<TeacherMobileApp> createState() => _TeacherMobileAppState();
}

class _TeacherMobileAppState extends State<TeacherMobileApp>
    with WidgetsBindingObserver {
  var _navigator = GlobalKey<NavigatorState>();
  String? _lastUid;
  @override
  void initState() {
    super.initState();
    _lastUid = widget.model.user?.uid;
    WidgetsBinding.instance.addObserver(this);
    widget.model.addListener(_notice);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notice();
    });
  }

  void _notice() {
    final vm = widget.model;
    if (vm.user?.uid != _lastUid) {
      _lastUid = vm.user?.uid;
      _navigator = GlobalKey<NavigatorState>();
    }
    final notice = vm.pendingNotice;
    if (notice == null || vm.user == null || vm.loadingWorkspace) return;
    vm.consumeNotice();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || vm.user == null) return;
      Widget destination = const NotificationsPage();
      try {
        if (notice.classId != null && notice.meetingId != null) {
          vm.meeting(notice.classId!, notice.meetingId!);
          destination = AttendancePage(
            classId: notice.classId!,
            meetingId: notice.meetingId!,
          );
        }
      } on Object {
        /* Unknown target stays in inbox; never guesses a class. */
      }
      _navigator.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => destination),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.model.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.model.removeListener(_notice);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: widget.model,
    child: Consumer<TeacherViewModel>(
      builder: (context, vm, _) => MaterialApp(
        key: ValueKey(vm.user?.uid),
        navigatorKey: _navigator,
        title: 'FAP Attendance',
        debugShowCheckedModeBanner: false,
        theme: mobileTheme(),
        builder: (context, child) => vm.user == null
            ? Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const TeacherSignInPage(),
                ),
              )
            : child!,
        home: vm.loadingWorkspace
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : vm.workspaceLoadFailed
            ? MobilePage(
                title: 'Mở dữ liệu',
                child: ContentList(
                  children: [
                    const SectionCard(
                      child: Text(
                        'Chưa mở được dữ liệu trên thiết bị. Hãy thử lại trước khi tạo workspace mới.',
                      ),
                    ),
                    FilledButton(
                      onPressed: vm.retryLoad,
                      child: const Text('Thử lại'),
                    ),
                    OutlinedButton(
                      onPressed: vm.busy ? null : vm.signOut,
                      child: const Text('Đăng xuất / Đổi tài khoản'),
                    ),
                  ],
                ),
              )
            : vm.workspace == null
            ? const WorkspaceStartPage()
            : const DashboardPage(),
      ),
    ),
  );
}

class TeacherSignInPage extends StatelessWidget {
  const TeacherSignInPage({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    return MobilePage(
      title: 'FAP Attendance',
      child: ContentList(
        children: [
          const SizedBox(height: 48),
          const Icon(Icons.school_rounded, size: 80, color: Color(0xFFC93C13)),
          Text(
            'Điểm danh thuận tiện\ntrên điện thoại',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const Text(
            'Dành cho giảng viên. Quản lý lớp, điểm danh qua link hoặc thủ công và lưu kết quả trên thiết bị.',
            textAlign: TextAlign.center,
          ),
          FilledButton.icon(
            onPressed: vm.busy
                ? null
                : () async {
                    await vm.signIn();
                  },
            icon: const Icon(Icons.login),
            label: const Text('Đăng nhập với Google'),
          ),
          const Text(
            'Dữ liệu được tách riêng theo tài khoản. Sao lưu đám mây là tùy chọn.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
