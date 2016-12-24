{-# Language OverloadedStrings #-}
module Rasa.Ext.Vim
  ( vim
  ) where

import Rasa.Ext
import Rasa.Ext.Files (save)
import Rasa.Ext.Cursors
import Rasa.Ext.Directive
import Rasa.Ext.StatusBar
import Rasa.Ext.Scheduler

import Control.Lens
import Control.Monad
import Data.Text.Lens (packed)
import Data.Default
import Data.Typeable
import qualified Data.Text as T

data VimSt
  = Normal
  | Insert
  deriving (Show, Typeable)

instance Default VimSt where
  def = Normal

getVim :: BufAction VimSt
getVim = use bufExt

setMode :: VimSt -> BufAction ()
setMode vimst = bufExt .= vimst

vim :: Scheduler ()
vim = do
  onEvent handleEvent
  beforeRender setStatus

handleEvent :: Action ()
handleEvent = do
  evts <- use events
  focMode <- focusDo $ do
    mode <- getVim
    case mode of
      Normal -> mapM_ normal evts
      Insert -> mapM_ insert evts
    return mode

  mapM_ (global focMode) evts

setStatus :: Action ()
setStatus = focusDo $ do
  mode <- getVim
  centerStatus $ show mode^.packed

global :: VimSt -> Event -> Action ()
global Normal (Keypress '+' _) = nextBuf
global Normal (Keypress '-' _) = prevBuf
global _ (Keypress 'c' [Ctrl]) = exit
global _ _ = return ()

insert :: Event -> BufAction ()
insert Esc = setMode Normal
insert BS = moveRangesByN (-1) >> delete
insert Enter = insertText "\n"
-- insert (Keypress 'w' [Ctrl]) = killWord
insert (Keypress c _) = insertText (T.singleton c) >> moveRangesByN 1
insert _ = return ()

normal :: Event -> BufAction ()
normal (Keypress 'i' _) = setMode Insert
normal (Keypress 'I' _) = startOfLine >> setMode Insert
normal (Keypress 'a' _) = moveRangesByN 1 >> setMode Insert
normal (Keypress 'A' _) = endOfLine >> setMode Insert
normal (Keypress '0' _) = startOfLine
normal (Keypress '$' _) = endOfLine
normal (Keypress 'g' _) = ranges .= [Range (Left . Offset $ 0) (Left . Offset $ 1)]

normal (Keypress 'G' _) = do
  txt <- use text
  ranges .= [Range (Left . Offset $ T.length txt - 1) (Left . Offset $ T.length txt)]

normal (Keypress 'o' _) = endOfLine >> insertText "\n" >> moveRangesByN 1 >> setMode Insert
normal (Keypress 'O' _) = startOfLine >> insertText "\n" >> setMode Insert
normal (Keypress 'h' _) = moveRangesByN (-1)
-- normal (Keypress 'H' _) = rangeDo_ $ addRange . addCoord (Coord 0 (-1))
normal (Keypress 'l' _) = moveRangesByN 1
-- normal (Keypress 'L' _) = rangeDo_ $ addRange . addCoord (Coord 0 1)
normal (Keypress 'k' _) = moveRangesByC $ Coord (-1) 0
-- normal (Keypress 'K' _) = rangeDo_ $ addRange . addCoord (Coord (-1) 0)
normal (Keypress 'j' _) = moveRangesByC $ Coord 1 0
normal (Keypress 'J' _) = rangeDo_ $ moveRangeByC (Coord 1 0) >=> addRange
normal (Keypress 'w' _) = findNext " " >> moveRangesByC (Coord 0 1)
normal (Keypress 'W' _) = rangeDo_ addCursor
  where
    addCursor (Range _ end) = do
      next <- findNextFrom " " end
      newStart <- moveCursorByN 1 next
      newEnd <- moveCursorByN 1 newStart
      addRange $ Range newStart newEnd

-- normal (Keypress 'B' _) = offsetsDo_ addCursor
--   where
--     addCursor o = do
--       newOffset <- findOffsetPrev " " (o - 1)
--       addCursorOffsetAt newOffset

normal (Keypress 'b' _) = moveRangesByN (-1) >> findPrev " "
normal (Keypress 'f' _) = findNext "f"
normal (Keypress 'F' _) = findPrev "f"
normal (Keypress 'X' _) = moveRangesByN (-1) >> delete
normal (Keypress 'x' _) = delete
normal (Keypress 's' [Ctrl]) = save
normal (Keypress ';' _) = ranges <~ use (ranges.reversed.to (take 1))
normal _ = return ()

endOfLine :: BufAction ()
endOfLine = findNext "\n"

startOfLine :: BufAction ()
startOfLine = findPrev "\n"

