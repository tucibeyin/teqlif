sealed class MediaUploadState {
  const MediaUploadState();
}

class UploadIdle extends MediaUploadState {
  const UploadIdle();
}

class UploadPicking extends MediaUploadState {
  const UploadPicking();
}

class UploadCompress extends MediaUploadState {
  const UploadCompress();
}

class UploadSending extends MediaUploadState {
  final double progress; // 0.0 – 1.0
  const UploadSending(this.progress);
}

class UploadDone extends MediaUploadState {
  const UploadDone();
}

class UploadFailed extends MediaUploadState {
  final String errorKey;
  final Object? retryPayload;
  const UploadFailed(this.errorKey, {this.retryPayload});
}
