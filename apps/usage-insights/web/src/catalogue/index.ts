import { HealthTable } from './HealthTable';
import { PaceStrip } from './PaceStrip';
import { RankedBars } from './RankedBars';
import { SessionTable } from './SessionTable';
import { StatTile } from './StatTile';
import { UnusedList } from './UnusedList';

/**
 * Every component a layout can place, by name. A layout refers to components by
 * these keys, so the AG-UI phase can place them from data it receives at runtime.
 */
export const catalogue = { StatTile, PaceStrip, RankedBars, SessionTable, HealthTable, UnusedList };

/** A key of {@link catalogue}. */
export type CatalogueName = keyof typeof catalogue;
