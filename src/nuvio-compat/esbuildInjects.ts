import {
  Buffer as CustomBuffer,
} from 'buffer';
import crypto from 'crypto'

export {
  // Replace global references with our imports.
  CustomBuffer as Buffer,
  crypto as 'crypto',
}
