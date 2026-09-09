/// GPS 座標卡爾曼濾波器，用於平滑跳躍點與降低測量雜訊
class CoordinateKalmanFilter {
  double _estimate;
  double _errorCovariance;
  final double _processNoise;

  CoordinateKalmanFilter(
    this._estimate, {
    double processNoise = 1e-6,
    double measurementNoise = 5.0,
  })  : _processNoise = processNoise,
        _errorCovariance = measurementNoise;

  double update(double measurement, {required double measurementNoise}) {
    _errorCovariance += _processNoise;
    final kalmanGain = _errorCovariance / (_errorCovariance + measurementNoise);
    _estimate += kalmanGain * (measurement - _estimate);
    _errorCovariance *= (1.0 - kalmanGain);
    return _estimate;
  }
}
