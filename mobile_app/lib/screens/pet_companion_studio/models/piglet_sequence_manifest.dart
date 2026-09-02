enum PigletSequenceType {
  idle,
  anticipate,
  chewing,
  celebration,
  sleep,
}

class PigletSequenceInfo {
  final PigletSequenceType type;
  final String directory;
  final int frameCount;
  final Duration frameDuration;
  final bool isLooping;

  const PigletSequenceInfo({
    required this.type,
    required this.directory,
    required this.frameCount,
    required this.frameDuration,
    required this.isLooping,
  });

  List<String> get framePaths {
    return List.generate(
      frameCount,
      (i) => '$directory/frame_${(i + 1).toString().padLeft(2, '0')}.png',
    );
  }
}

class PigletSequenceManifest {
  static const PigletSequenceInfo idle = PigletSequenceInfo(
    type: PigletSequenceType.idle,
    directory: 'assets/images/pet_seq_idle',
    frameCount: 4,
    frameDuration: Duration(milliseconds: 2400),
    isLooping: true,
  );

  static const PigletSequenceInfo anticipate = PigletSequenceInfo(
    type: PigletSequenceType.anticipate,
    directory: 'assets/images/pet_seq_anticipate',
    frameCount: 4,
    frameDuration: Duration(milliseconds: 800),
    isLooping: true,
  );

  static const PigletSequenceInfo chewing = PigletSequenceInfo(
    type: PigletSequenceType.chewing,
    directory: 'assets/images/pet_seq_chewing',
    frameCount: 4,
    frameDuration: Duration(milliseconds: 1000),
    isLooping: true,
  );

  static const PigletSequenceInfo celebration = PigletSequenceInfo(
    type: PigletSequenceType.celebration,
    directory: 'assets/images/pet_seq_celebration',
    frameCount: 4,
    frameDuration: Duration(milliseconds: 1000),
    isLooping: false,
  );

  static const PigletSequenceInfo sleep = PigletSequenceInfo(
    type: PigletSequenceType.sleep,
    directory: 'assets/images/pet_seq_sleep',
    frameCount: 4,
    frameDuration: Duration(milliseconds: 2800),
    isLooping: true,
  );

  static PigletSequenceInfo getInfo(PigletSequenceType type) {
    switch (type) {
      case PigletSequenceType.anticipate:
        return anticipate;
      case PigletSequenceType.chewing:
        return chewing;
      case PigletSequenceType.celebration:
        return celebration;
      case PigletSequenceType.sleep:
        return sleep;
      case PigletSequenceType.idle:
      default:
        return idle;
    }
  }
}
