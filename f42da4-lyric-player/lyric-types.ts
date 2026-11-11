/** One sung word: seconds of its own mix. */
export interface TimedWord {
  end: number;
  start: number;
  /** shown in caps */
  text: string;
}

export interface TimedLine {
  /** index into `sections` */
  section: number;
  /** English of a line with Korean in it, empty otherwise */
  translation: string;
  words: TimedWord[];
}

/** What `align_lyrics.py` writes for one mix. */
export interface SongLyrics {
  lines: TimedLine[];
  sections: string[];
}
