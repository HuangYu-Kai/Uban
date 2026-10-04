import 'package:latlong2/latlong.dart';

/// 長輩的常去地點（家、公園、市場…），由家屬在地圖畫面設定。
///
/// 對應後端 `/location/places` 的 Place JSON：
/// `{id, name, latitude, longitude, radius_m, is_home}`。
/// 不可變物件；其中 [isHome] 為 true 的地點是「家」（每位長輩最多一個）。
class ElderPlace {
  final int id;
  final String name;
  final double latitude;
  final double longitude;

  /// 到訪判定半徑（公尺）。
  final int radiusM;
  final bool isHome;

  const ElderPlace({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusM,
    required this.isHome,
  });

  LatLng get position => LatLng(latitude, longitude);

  /// 欄位缺漏或型別不符時，`radius_m` 退回 100、`is_home` 退回 false、
  /// `name` 退回空字串；`id`、座標是必要欄位，缺漏會拋 [FormatException]。
  factory ElderPlace.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final lat = json['latitude'];
    final lng = json['longitude'];
    if (id is! num || lat is! num || lng is! num) {
      throw FormatException('ElderPlace.fromJson: 缺少 id／座標: $json');
    }
    final radius = json['radius_m'];
    return ElderPlace(
      id: id.toInt(),
      name: (json['name'] ?? '').toString(),
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      radiusM: radius is num ? radius.toInt() : 100,
      isHome: json['is_home'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius_m': radiusM,
        'is_home': isHome,
      };

  @override
  bool operator ==(Object other) =>
      other is ElderPlace &&
      other.id == id &&
      other.name == name &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.radiusM == radiusM &&
      other.isHome == isHome;

  @override
  int get hashCode => Object.hash(id, name, latitude, longitude, radiusM, isHome);
}
