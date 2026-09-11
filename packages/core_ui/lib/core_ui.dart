/// Public surface of `core_ui`.
///
/// Material 3 theme (light/dark/dynamic-color), design tokens, and the
/// shared widget vocabulary used by both the app shell and every service
/// module.
library;

// M3 pull-to-refresh from m3_expressive, surfaced through core_ui so modules
// use it without each taking a direct m3_expressive dependency.
export 'package:easy_refresh/easy_refresh.dart' hide EasyRefresh, HeaderLocator;
export 'package:flex_color_scheme/flex_color_scheme.dart';

export 'src/artwork_headers.dart';
export 'src/design_tokens.dart';
export 'src/navigation.dart';
export 'src/performance_logger.dart';
export 'src/service_visuals.dart';
export 'src/theme.dart';
export 'src/widgets/async_value_view.dart';
export 'src/widgets/atrium_network_image.dart';
export 'src/widgets/beta_badge.dart';
export 'src/widgets/bottom_nav.dart';
export 'src/widgets/collapsed_title.dart';
export 'src/widgets/easy_refresh_wrapper.dart';
export 'src/widgets/expressive_progress_indicator.dart';
export 'src/widgets/expressive_slider.dart';
export 'src/widgets/overview_box.dart';
export 'src/widgets/service_tile.dart';
export 'src/widgets/state_views.dart';
export 'src/widgets/status_chip.dart';
