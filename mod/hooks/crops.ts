import type { Crop, Farm } from '../types'

// The three crops, in the order the fields are drawn, and where each one's
// harvest lands in the barn: the single place both the economy and the canvas
// read.

export const RIPE = 3

export const CROP_NAMES: Crop[] = ['tobacco', 'corn', 'apples']

export const CROP_BARN: Record<Crop, 'bales' | 'corn' | 'apples'> = {
  tobacco: 'bales',
  corn: 'corn',
  apples: 'apples',
}

