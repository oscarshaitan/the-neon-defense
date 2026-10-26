/**
 * Visual Theme definitions for cyberpunk-neon aesthetic
 */
export const THEME = {
  primary: '#00f0ff', // Electric cyan
  secondary: '#ff007f', // Neon magenta
  accent: '#a855f7', // Violet
  warning: '#eab308', // Amber pulse
  success: '#10b981', // Matrix emerald
  darkBg: '#040711',
  panelBg: 'rgba(6, 12, 28, 0.92)',
  panelBorder: 'rgba(0, 240, 255, 0.4)',
  fontFamily: '"Chakra Petch", "Rajdhani", system-ui, sans-serif',
};

/**
 * Configuration for the game.
 */
export const CONFIG = {
  // Game Initialization
  title: {
    value: 'Neon Defense',
    type: 'string',
    label: 'Game Title',
    group: 'GAME',
  },
  baseCanvasWidth: {
    value: 1376,
    type: 'number',
    label: 'Base Canvas Width',
    group: 'GAME',
  },
  baseCanvasHeight: {
    value: 768,
    type: 'number',
    label: 'Base Canvas Height',
    group: 'GAME',
  },

  // System Constants
  targetFPS: {
    value: 60,
    type: 'number',
    label: 'Target FPS',
    group: 'SYSTEM',
  },
  stepMs: {
    value: 1000 / 60,
    type: 'number',
    label: 'Step MS',
    group: 'SYSTEM',
  },
  maxSubSteps: {
    value: 5,
    type: 'number',
    label: 'Max Sub Steps',
    group: 'SYSTEM',
  },

  // Visual Theme
  backgroundColor: {
    value: '#040711',
    type: 'color',
    label: 'Background Color',
    group: 'THEME',
  },
  primaryColor: {
    value: '#00f0ff',
    type: 'color',
    label: 'Primary Color',
    group: 'THEME',
  },
  fontFamily: {
    value: '"Chakra Petch", sans-serif',
    type: 'string',
    label: 'Font Family',
    group: 'THEME',
  },

  // Audio Levels
  defaultMusicVolume: {
    value: 0.6,
    type: 'number',
    label: 'Default Music Volume',
    group: 'AUDIO',
  },
  defaultSfxVolume: {
    value: 0.7,
    type: 'number',
    label: 'Default SFX Volume',
    group: 'AUDIO',
  },

  // Rules & Difficulty
  startingCredits: {
    value: 200,
    type: 'number',
    label: 'Starting Credits',
    group: 'Rules',
  },
  coreMaxLives: {
    value: 20,
    type: 'number',
    label: 'Core Max Lives',
    group: 'Rules',
  },
  coreMaxHealth: {
    value: 20,
    type: 'number',
    label: 'Core Max Lives',
    group: 'Rules',
  },
  empCooldown: {
    value: 25,
    type: 'number',
    label: 'EMP Cooldown (s)',
    group: 'Rules',
  },
  overclockCooldown: {
    value: 20,
    type: 'number',
    label: 'Overclock Cooldown (s)',
    group: 'Rules',
  },
  repairBaseCost: {
    value: 100,
    type: 'number',
    label: 'Base Repair Cost',
    group: 'Rules',
  },
  prepPhaseDuration: {
    value: 30,
    type: 'number',
    label: 'Prep Phase Duration (s)',
    group: 'Rules',
  },
  totalWaves: {
    value: 100,
    type: 'number',
    label: 'Total Waves',
    group: 'Rules',
  },
};

/**
 * Audio tracks registry for dynamic soundtrack switching
 */
export const AUDIO_TRACKS = {
  tactical: 'assets/audio/bgm_tactical_synth.mp3',
  boss: 'assets/audio/bgm_boss_clash.mp3',
  mutation: 'assets/audio/bgm_mutation_surge.mp3',
} as const;

export type AudioTrackType = keyof typeof AUDIO_TRACKS;

// Merge customized config values if present (injected by Playground)
const {playgroundConfig} = globalThis as {
  playgroundConfig?: Record<string, unknown>;
};
if (playgroundConfig) {
  for (const [key, value] of Object.entries(playgroundConfig)) {
    if (key in CONFIG) {
      Object.assign(CONFIG[key as keyof typeof CONFIG], {value});
    }
  }
}

/**
 * Type helper for reading values in game code
 */
export type ConfigKey = keyof typeof CONFIG;

/**
 * Gets a configuration value by key.
 * @param key The configuration key.
 * @return The configuration value.
 */
export function getConfig<K extends ConfigKey>(
  key: K,
): (typeof CONFIG)[K]['value'] {
  return CONFIG[key].value;
}
