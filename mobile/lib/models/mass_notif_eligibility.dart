enum MassNotifUnavailableReason {
  listingNotActive,
  // ileride: insufficientBalance, featureNotUnlocked
}

sealed class MassNotifEligibility {
  const MassNotifEligibility();
}

/// Kullanıcı blast gönderebilir.
final class MassNotifAvailable extends MassNotifEligibility {
  const MassNotifAvailable();
}

/// Cooldown aktif — kaç saniye kaldığını taşır, UI'ın rapor linkini göstermesi için.
final class MassNotifCooldownActive extends MassNotifEligibility {
  const MassNotifCooldownActive(this.secondsRemaining);
  final int secondsRemaining;
}

/// Blast gönderilemez; sebep enum ile taşınır.
final class MassNotifUnavailable extends MassNotifEligibility {
  const MassNotifUnavailable(this.reason);
  final MassNotifUnavailableReason reason;
}
