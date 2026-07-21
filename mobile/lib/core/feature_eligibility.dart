sealed class FeatureEligibility {
  const FeatureEligibility();
  bool get isAvailable => this is FeatureAvailable;
}

final class FeatureAvailable extends FeatureEligibility {
  const FeatureAvailable();
}

final class FeatureUnavailable extends FeatureEligibility {
  const FeatureUnavailable(this.reason);
  final Object reason;
}
