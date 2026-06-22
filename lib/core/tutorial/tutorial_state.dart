/// Immutable state for the in-app tutorial system.
class TutorialState {
  final int stepIndex;
  final int totalSteps;

  const TutorialState({
    required this.stepIndex,
    required this.totalSteps,
  });

  /// Convenience constructor for the inactive / idle state.
  const TutorialState.inactive()
      : stepIndex = 0,
        totalSteps = 0;

  bool get isActive => totalSteps > 0;

  TutorialState copyWith({int? stepIndex, int? totalSteps}) {
    return TutorialState(
      stepIndex: stepIndex ?? this.stepIndex,
      totalSteps: totalSteps ?? this.totalSteps,
    );
  }
}
