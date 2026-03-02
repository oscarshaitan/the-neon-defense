// --- Game Control ---
function maybeStartFirstRunTutorial() {
    const tutorialAlreadySeen = localStorage.getItem(tutorialSeenKey) === 'true';
    if (tutorialAlreadySeen || completedTutorial) return;
    localStorage.setItem(tutorialSeenKey, 'true');
    startTutorial();
}

window.startGame = function () {
    AudioEngine.init(); // Initialize audio context on start
    document.getElementById('start-screen').classList.add('hidden');
    resetGameLogic();
    gameState = 'playing';
    saveGame();
    maybeStartFirstRunTutorial();
};

window.resetGame = function () {
    AudioEngine.init();
    // This is "Game Over" restart aka System Reboot
    // We can just wipe save and start fresh
    fullReset();
};

window.fullReset = function () {
    localStorage.removeItem('neonDefenseSave');
    localStorage.removeItem('neonDefenseTutorialComplete');
    localStorage.removeItem(onboardingHintKey);
    localStorage.removeItem(onboardingHintVersionKey);
    location.reload();
};

window.resetTutorial = function () {
    localStorage.removeItem('neonDefenseTutorialComplete');
    localStorage.removeItem(tutorialSeenKey);
    localStorage.removeItem(onboardingHintKey);
    localStorage.removeItem(onboardingHintVersionKey);
    location.reload();
};

function togglePause() {
    isPaused = !isPaused;
    if (isPaused) {
        document.getElementById('pause-menu').classList.remove('hidden');
    } else {
        document.getElementById('pause-menu').classList.add('hidden');
        showNextHint();
    }
}

