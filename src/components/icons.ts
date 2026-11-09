/**
 * Maps the icon keys used in content.ts to lucide-react components,
 * so copy can be edited without importing icons.
 */
import {
  Building2,
  CalendarPlus,
  CalendarRange,
  Compass,
  Database,
  Handshake,
  Landmark,
  ListChecks,
  Users,
  type LucideIcon,
} from 'lucide-react';

export const ICONS: Record<string, LucideIcon> = {
  pipeline: CalendarRange,
  fit: Compass,
  shortlist: ListChecks,
  support: Handshake,
  bureau: Landmark,
  venue: Building2,
  owner: Users,
  submit: CalendarPlus,
  partner: Database,
};
