;;; window.el --- GNU Emacs window commands aside from those written in C

;; Copyright (C) 1985, 1989, 1992-1994, 2000-2011
;;   Free Software Foundation, Inc.

;; Maintainer: FSF
;; Keywords: internal
;; Package: emacs

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Window tree functions.

;;; Code:

(eval-when-compile (require 'cl))

(defmacro save-selected-window (&rest body)
  "Execute BODY, then select the previously selected window.
The value returned is the value of the last form in BODY.

This macro saves and restores the selected window, as well as the
selected window in each frame.  If the previously selected window
is no longer live, then whatever window is selected at the end of
BODY remains selected.  If the previously selected window of some
frame is no longer live at the end of BODY, that frame's selected
window is left alone.

This macro saves and restores the current buffer, since otherwise
its normal operation could make a different buffer current.  The
order of recently selected windows and the buffer list ordering
are not altered by this macro (unless they are altered in BODY)."
  (declare (indent 0) (debug t))
  `(let ((save-selected-window-window (selected-window))
	 ;; It is necessary to save all of these, because calling
	 ;; select-window changes frame-selected-window for whatever
	 ;; frame that window is in.
	 (save-selected-window-alist
	  (mapcar (lambda (frame) (cons frame (frame-selected-window frame)))
		  (frame-list))))
     (save-current-buffer
       (unwind-protect
	   (progn ,@body)
	 (dolist (elt save-selected-window-alist)
	   (and (frame-live-p (car elt))
		(window-live-p (cdr elt))
		(set-frame-selected-window (car elt) (cdr elt) 'norecord)))
	 (when (window-live-p save-selected-window-window)
	   (select-window save-selected-window-window 'norecord))))))

;; The following two functions are like `window-next' and `window-prev'
;; but the WINDOW argument is _not_ optional (so they don't substitute
;; the selected window for nil), and they return nil when WINDOW doesn't
;; have a parent (like a frame's root window or a minibuffer window).
(defsubst window-right (window)
  "Return WINDOW's right sibling.
Return nil if WINDOW is the root window of its frame.  WINDOW can
be any window."
  (and window (window-parent window) (window-next window)))

(defsubst window-left (window)
  "Return WINDOW's left sibling.
Return nil if WINDOW is the root window of its frame.  WINDOW can
be any window."
  (and window (window-parent window) (window-prev window)))

(defsubst window-child (window)
  "Return WINDOW's first child window."
  (or (window-vchild window) (window-hchild window)))

(defun window-child-count (window)
  "Return number of WINDOW's child windows."
  (let ((count 0))
    (when (and (windowp window) (setq window (window-child window)))
      (while window
	(setq count (1+ count))
	(setq window (window-next window))))
    count))

(defun window-last-child (window)
  "Return last child window of WINDOW."
  (when (and (windowp window) (setq window (window-child window)))
    (while (window-next window)
      (setq window (window-next window))))
  window)

(defsubst window-any-p (object)
  "Return t if OBJECT denotes a live or internal window."
  (and (windowp object)
       (or (window-buffer object) (window-child object))
       t))

;; The following four functions should probably go to subr.el.
(defsubst normalize-live-buffer (buffer-or-name)
  "Return buffer specified by BUFFER-OR-NAME.
BUFFER-OR-NAME must be either a buffer or a string naming a live
buffer and defaults to the current buffer."
  (cond
   ((not buffer-or-name)
    (current-buffer))
   ((bufferp buffer-or-name)
    (if (buffer-live-p buffer-or-name)
	buffer-or-name
      (error "Buffer %s is not a live buffer" buffer-or-name)))
   ((get-buffer buffer-or-name))
   (t
    (error "No such buffer %s" buffer-or-name))))

(defsubst normalize-live-frame (frame)
  "Return frame specified by FRAME.
FRAME must be a live frame and defaults to the selected frame."
  (if frame
      (if (frame-live-p frame)
	  frame
	(error "%s is not a live frame" frame))
    (selected-frame)))

(defsubst normalize-any-window (window)
  "Return window specified by WINDOW.
WINDOW must be a window that has not been deleted and defaults to
the selected window."
  (if window
      (if (window-any-p window)
	  window
	(error "%s is not a window" window))
    (selected-window)))

(defsubst normalize-live-window (window)
  "Return live window specified by WINDOW.
WINDOW must be a live window and defaults to the selected one."
  (if window
      (if (and (windowp window) (window-buffer window))
	  window
	(error "%s is not a live window" window))
    (selected-window)))

(defvar ignore-window-parameters nil
  "If non-nil, standard functions ignore window parameters.
The functions currently affected by this are `split-window',
`delete-window', `delete-other-windows' and `other-window'.

An application may bind this to a non-nil value around calls to
these functions to inhibit processing of window parameters.")

(defconst window-safe-min-height 1
  "The absolut minimum number of lines of a window.
Anything less might crash Emacs.")

(defcustom window-min-height 4
  "The minimum number of lines of any window.
The value has to accomodate a mode- or header-line if present.  A
value less than `window-safe-min-height' is ignored.  The value
of this variable is honored when windows are resized or split.

Applications should never rebind this variable.  To resize a
window to a height less than the one specified here, an
application should instead call `resize-window' with a non-nil
IGNORE argument.  In order to have `split-window' make a window
shorter, explictly specify the SIZE argument of that function."
  :type 'integer
  :version "24.1"
  :group 'windows)

(defconst window-safe-min-width 2
  "The absolut minimum number of columns of a window.
Anything less might crash Emacs.")

(defcustom window-min-width 10
  "The minimum number of columns of any window.
The value has to accomodate margins, fringes, or scrollbars if
present.  A value less than `window-safe-min-width' is ignored.
The value of this variable is honored when windows are resized or
split.

Applications should never rebind this variable.  To resize a
window to a width less than the one specified here, an
application should instead call `resize-window' with a non-nil
IGNORE argument.  In order to have `split-window' make a window
narrower, explictly specify the SIZE argument of that function."
  :type 'integer
  :version "24.1"
  :group 'windows)

(defun window-iso-combination-p (&optional window horizontal)
  "If WINDOW is a vertical combination return WINDOW's first child.
WINDOW can be any window and defaults to the selected one.
Optional argument HORIZONTAL non-nil means return WINDOW's first
child if WINDOW is a horizontal combination."
  (setq window (normalize-any-window window))
  (if horizontal
      (window-hchild window)
    (window-vchild window)))

(defsubst window-iso-combined-p (&optional window horizontal)
  "Return non-nil if and only if WINDOW is vertically combined.
WINDOW can be any window and defaults to the selected one.
Optional argument HORIZONTAL non-nil means return non-nil if and
only if WINDOW is horizontally combined."
  (setq window (normalize-any-window window))
  (let ((parent (window-parent window)))
    (and parent (window-iso-combination-p parent horizontal))))

(defun window-iso-combinations (&optional window horizontal)
  "Return largest number of vertically arranged subwindows of WINDOW.
WINDOW can be any window and defaults to the selected one.
Optional argument HORIZONTAL non-nil means to return the largest
number of horizontally arranged subwindows of WINDOW."
  (setq window (normalize-any-window window))
  (cond
   ((window-live-p window)
    ;; If WINDOW is live, return 1.
    1)
   ((window-iso-combination-p window horizontal)
    ;; If WINDOW is iso-combined, return the sum of the values for all
    ;; subwindows of WINDOW.
    (let ((child (window-child window))
	  (count 0))
      (while child
	(setq count
	      (+ (window-iso-combinations child horizontal)
		 count))
	(setq child (window-right child)))
      count))
   (t
    ;; If WINDOW is not iso-combined, return the maximum value of any
    ;; subwindow of WINDOW.
    (let ((child (window-child window))
	  (count 1))
      (while child
	(setq count
	      (max (window-iso-combinations child horizontal)
		   count))
	(setq child (window-right child)))
      count))))

(defun walk-window-tree-1 (proc walk-window-tree-window any &optional sub-only)
  "Helper function for `walk-window-tree' and `walk-window-subtree'."
  (let (walk-window-tree-buffer)
    (while walk-window-tree-window
      (setq walk-window-tree-buffer
	    (window-buffer walk-window-tree-window))
      (when (or walk-window-tree-buffer any)
	(funcall proc walk-window-tree-window))
      (unless walk-window-tree-buffer
	(walk-window-tree-1
	 proc (window-hchild walk-window-tree-window) any)
	(walk-window-tree-1
	 proc (window-vchild walk-window-tree-window) any))
      (if sub-only
	  (setq walk-window-tree-window nil)
	(setq walk-window-tree-window
	      (window-right walk-window-tree-window))))))

(defun walk-window-tree (proc &optional frame any)
  "Run function PROC on each live window of FRAME.
PROC must be a function with one argument - a window.  FRAME must
be a live frame and defaults to the selected one.  ANY, if
non-nil means to run PROC on all live and internal windows of
FRAME.

This function performs a pre-order, depth-first traversal of the
window tree.  If PROC changes the window tree, the result is
unpredictable."
  (let ((walk-window-tree-frame (normalize-live-frame frame)))
    (walk-window-tree-1
     proc (frame-root-window walk-window-tree-frame) any)))

(defun walk-window-subtree (proc &optional window any)
  "Run function PROC on each live subwindow of WINDOW.
WINDOW defaults to the selected window.  PROC must be a function
with one argument - a window.  ANY, if non-nil means to run PROC
on all live and internal subwindows of WINDOW.

This function performs a pre-order, depth-first traversal of the
window tree rooted at WINDOW.  If PROC changes that window tree,
the result is unpredictable."
  (setq window (normalize-any-window window))
  (walk-window-tree-1 proc window any t))

(defun windows-with-parameter (parameter &optional value frame any values)
  "Return a list of all windows on FRAME with PARAMETER non-nil.
FRAME defaults to the selected frame.  Optional argument VALUE
non-nil means only return windows whose window-parameter value of
PARAMETER equals VALUE \(comparison is done using `equal').
Optional argument ANY non-nil means consider internal windows
too.  Optional argument VALUES non-nil means return a list of cons
cells whose car is the value of the parameter and whose cdr is
the window."
  (let (this-value windows)
    (walk-window-tree
     (lambda (window)
       (when (and (setq this-value (window-parameter window parameter))
		  (or (not value) (or (equal value this-value))))
	   (setq windows
		 (if values
		     (cons (cons this-value window) windows)
		   (cons window windows)))))
     frame any)

    (nreverse windows)))

(defun window-with-parameter (parameter &optional value frame any)
  "Return first window on FRAME with PARAMETER non-nil.
FRAME defaults to the selected frame.  Optional argument VALUE
non-nil means only return a window whose window-parameter value
for PARAMETER equals VALUE \(comparison is done with `equal').
Optional argument ANY non-nil means consider internal windows
too."
  (let (this-value windows)
    (catch 'found
      (walk-window-tree
       (lambda (window)
	 (when (and (setq this-value (window-parameter window parameter))
		    (or (not value) (equal value this-value)))
	   (throw 'found window)))
       frame any))))

;;; Atomic windows.
(defun window-atom-root (&optional window)
  "Return root of atomic window WINDOW is a part of.
WINDOW can be any window and defaults to the selected one.
Return nil if WINDOW is not part of a atomic window."
  (setq window (normalize-any-window window))
  (let (root)
    (while (and window (window-parameter window 'window-atom))
      (setq root window)
      (setq window (window-parent window)))
    root))

(defun make-window-atom (window)
  "Make WINDOW an atomic window.
WINDOW must be an internal window.  Return WINDOW."
  (if (not (window-child window))
      (error "Window %s is not an internal window" window)
    (walk-window-subtree
     (lambda (window)
       (set-window-parameter window 'window-atom t))
     window t)
    window))

(defun window-atom-check-1 (window)
  "Subroutine of `window-atom-check'."
  (when window
    (if (window-parameter window 'window-atom)
	(let ((count 0))
	  (when (or (catch 'reset
		      (walk-window-subtree
		       (lambda (window)
			 (if (window-parameter window 'window-atom)
			     (setq count (1+ count))
			   (throw 'reset t)))
		       window t))
		    ;; count >= 1 must hold here.  If there's no other
		    ;; window around dissolve this atomic window.
		    (= count 1))
	    ;; Dissolve atomic window.
	    (walk-window-subtree
	     (lambda (window)
	       (set-window-parameter window 'window-atom nil))
	     window t)))
      ;; Check children.
      (unless (window-buffer window)
	(window-atom-check-1 (window-hchild window))
	(window-atom-check-1 (window-vchild window))))
    ;; Check right sibling
    (window-atom-check-1 (window-right window))))

(defun window-atom-check (&optional frame)
  "Check atomicity of all windows on FRAME.
FRAME defaults to the selected frame.  If an atomic window is
wrongly configured, reset the atomicity of all its subwindows to
nil.  An atomic window is wrongly configured if it has no
subwindows or one of its subwindows is not atomic."
  (window-atom-check-1 (frame-root-window frame)))

;; Side windows.
(defvar window-sides '(left top right bottom)
  "Window sides.")

(defcustom window-sides-vertical nil
  "If non-nil, left and right side windows are full height.
Otherwise, top and bottom side windows are full width."
  :type 'boolean
  :group 'windows
  :version "24.1")

(defcustom window-sides-slots '(nil nil nil nil)
  "Maximum number of side window slots.
The value is a list of four elements specifying the number of
side window slots on \(in this order) the left, top, right and
bottom side of each frame.  If an element is a number, this means
to display at most that many side windows on the corresponding
side.  If an element is nil, this means there's no bound on the
number of slots on that side."
  :risky t
  :type
  '(list
    :value (nil nil nil nil)
    (choice
     :tag "Left"
     :help-echo "Maximum slots of left side window."
     :value nil
     :format "%[Left%] %v\n"
     (const :tag "Unlimited" :format "%t" nil)
     (integer :tag "Number" :value 2 :size 5))
    (choice
     :tag "Top"
     :help-echo "Maximum slots of top side window."
     :value nil
     :format "%[Top%] %v\n"
     (const :tag "Unlimited" :format "%t" nil)
     (integer :tag "Number" :value 3 :size 5))
    (choice
     :tag "Right"
     :help-echo "Maximum slots of right side window."
     :value nil
     :format "%[Right%] %v\n"
     (const :tag "Unlimited" :format "%t" nil)
     (integer :tag "Number" :value 2 :size 5))
    (choice
     :tag "Bottom"
     :help-echo "Maximum slots of bottom side window."
     :value nil
     :format "%[Bottom%] %v\n"
     (const :tag "Unlimited" :format "%t" nil)
     (integer :tag "Number" :value 3 :size 5)))
  :group 'windows)

(defun window-side-check (&optional frame)
  "Check the window-side parameter of all windows on FRAME.
FRAME defaults to the selected frame.  If the configuration is
invalid, reset all window-side parameters to nil.

A valid configuration has to preserve the following invariant:

- If a window has a non-nil window-side parameter, it must have a
  parent window and the parent window's window-side parameter
  must be either nil or the same as for window.

- If windows with non-nil window-side parameters exist, there
  must be at most one window of each side and non-side with a
  parent whose window-side parameter is nil and there must be no
  leaf window whose window-side parameter is nil."
  (let (normal none left top right bottom
	side parent parent-side code)
    (when (or (catch 'reset
		(walk-window-tree
		 (lambda (window)
		   (setq side (window-parameter window 'window-side))
		   (setq parent (window-parent window))
		   (setq parent-side
			 (and parent (window-parameter parent 'window-side)))
		   ;; The following `cond' seems a bit tedious, but I'd
		   ;; rather stick to using just the stack.
		   (cond
		    (parent-side
		     (when (not (eq parent-side side))
		       ;; A parent whose window-side is non-nil must
		       ;; have a child with the same window-side.
		       (throw 'reset t)))
		    ;; Now check that there's more than one main window
		    ;; for any of none, left, top, right and bottom.
		    ((eq side 'none)
		     (if none
			 (throw 'reset t)
		       (setq none t)))
		    ((eq side 'left)
		     (if left
			 (throw 'reset t)
		       (setq left t)))
		    ((eq side 'top)
		     (if top
			 (throw 'reset t)
		       (setq top t)))
		    ((eq side 'right)
		     (if right
			 (throw 'reset t)
		       (setq right t)))
		    ((eq side 'bottom)
		     (if bottom
			 (throw 'reset t)
		       (setq bottom t)))
		    ((window-buffer window)
		     ;; A leaf window without window-side parameter,
		     ;; record its existence.
		     (setq normal t))))
		 frame t))
	      (if none
		  ;; At least one non-side window exists, so there must
		  ;; be at least one side-window and no normal window.
		  (or (not (or left top right bottom)) normal)
		;; No non-side window exists, so there must be no side
		;; window either.
		(or left top right bottom)))
      (walk-window-tree
       (lambda (window)
	 (set-window-parameter window 'window-side nil))
       frame t))))

(defun window-check (&optional frame)
  "Check atomic and side windows on FRAME.
FRAME defaults to the selected frame."
  (window-side-check frame)
  (window-atom-check frame))

;;; Window sizes.
(defvar window-size-fixed nil
  "Non-nil in a buffer means windows displaying the buffer are fixed-size.
If the value is `height', then only the window's height is fixed.
If the value is `width', then only the window's width is fixed.
Any other non-nil value fixes both the width and the height.

Emacs won't change the size of any window displaying that buffer,
unless it has no other choice \(like when deleting a neighboring
window).")
(make-variable-buffer-local 'window-size-fixed)

(defsubst window-size-ignore (window ignore)
  "Return non-nil if IGNORE says to ignore size restrictions for WINDOW."
  (if (window-any-p ignore) (eq window ignore) ignore))

(defun window-min-size (&optional window horizontal ignore)
  "Return the minimum number of lines of WINDOW.
WINDOW can be an arbitrary window and defaults to the selected
one.  Optional argument HORIZONTAL non-nil means return the
minimum number of columns of WINDOW.

Optional argument IGNORE non-nil means ignore any restrictions
imposed by fixed size windows, `window-min-height' or
`window-min-width' settings.  IGNORE equal `safe' means live
windows may get as small as `window-safe-min-height' lines and
`window-safe-min-width' columns.  IGNORE a window means ignore
restrictions for that window only."
  (window-min-size-1
   (normalize-any-window window) horizontal ignore))

(defun window-min-size-1 (window horizontal ignore)
  "Internal function of `window-min-size'."
  (let ((sub (window-child window)))
    (if sub
	(let ((value 0))
	  ;; WINDOW is an internal window.
	  (if (window-iso-combined-p sub horizontal)
	      ;; The minimum size of an iso-combination is the sum of
	      ;; the minimum sizes of its subwindows.
	      (while sub
		(setq value (+ value
			       (window-min-size-1 sub horizontal ignore)))
		(setq sub (window-right sub)))
	    ;; The minimum size of an ortho-combination is the maximum of
	    ;; the minimum sizes of its subwindows.
	    (while sub
	      (setq value (max value
			       (window-min-size-1 sub horizontal ignore)))
	      (setq sub (window-right sub))))
	  value)
      (with-current-buffer (window-buffer window)
	(cond
	 ((and (not (window-size-ignore window ignore))
	       (window-size-fixed-p window horizontal))
	  ;; The minimum size of a fixed size window is its size.
	  (window-total-size window horizontal))
	 ((or (eq ignore 'safe) (eq ignore window))
	  ;; If IGNORE equals `safe' or WINDOW return the safe values.
	  (if horizontal window-safe-min-width window-safe-min-height))
	 (horizontal
	  ;; For the minimum width of a window take fringes and
	  ;; scroll-bars into account.  This is questionable and should
	  ;; be removed as soon as we are able to split (and resize)
	  ;; windows such that the new (or resized) windows can get a
	  ;; size less than the user-specified `window-min-height' and
	  ;; `window-min-width'.
	  (let ((frame (window-frame window))
		(fringes (window-fringes window))
		(scroll-bars (window-scroll-bars window)))
	    (max
	     (+ window-safe-min-width
		(ceiling (car fringes) (frame-char-width frame))
		(ceiling (cadr fringes) (frame-char-width frame))
		(cond
		 ((memq (nth 2 scroll-bars) '(left right))
		  (nth 1 scroll-bars))
		 ((memq (frame-parameter frame 'vertical-scroll-bars)
			'(left right))
		  (ceiling (or (frame-parameter frame 'scroll-bar-width) 14)
			   (frame-char-width)))
		 (t 0)))
	     (if (and (not (window-size-ignore window ignore))
		      (numberp window-min-width))
		 window-min-width
	       0))))
	 (t
	  ;; For the minimum height of a window take any mode- or
	  ;; header-line into account.
	  (max (+ window-safe-min-height
		  (if header-line-format 1 0)
		  (if mode-line-format 1 0))
	       (if (and (not (window-size-ignore window ignore))
			(numberp window-min-height))
		   window-min-height
		 0))))))))

(defun window-sizable (window delta &optional horizontal ignore)
  "Return DELTA if DELTA lines can be added to WINDOW.
Optional argument HORIZONTAL non-nil means return DELTA if DELTA
columns can be added to WINDOW.  A return value of zero means
that no lines (or columns) can be added to WINDOW.

This function looks only at WINDOW and its subwindows.  The
function `window-resizable' looks at other windows as well.

DELTA positive means WINDOW shall be enlarged by DELTA lines or
columns.  If WINDOW cannot be enlarged by DELTA lines or columns
return the maximum value in the range 0..DELTA by which WINDOW
can be enlarged.

DELTA negative means WINDOW shall be shrunk by -DELTA lines or
columns.  If WINDOW cannot be shrunk by -DELTA lines or columns,
return the minimum value in the range DELTA..0 by which WINDOW
can be shrunk.

Optional argument IGNORE non-nil means ignore any restrictions
imposed by fixed size windows, `window-min-height' or
`window-min-width' settings.  IGNORE equal `safe' means live
windows may get as small as `window-safe-min-height' lines and
`window-safe-min-width' columns.  IGNORE any window means ignore
restrictions for that window only."
  (setq window (normalize-any-window window))
  (cond
   ((< delta 0)
    (max (- (window-min-size window horizontal ignore)
	    (window-total-size window horizontal))
	 delta))
   ((window-size-ignore window ignore)
    delta)
   ((> delta 0)
    (if (window-size-fixed-p window horizontal)
	0
      delta))
   (t 0)))

(defsubst window-sizable-p (window delta &optional horizontal ignore)
  "Return t if WINDOW can be resized by DELTA lines.
For the meaning of the arguments of this function see the
doc-string of `window-sizable'."
  (setq window (normalize-any-window window))
  (if (> delta 0)
      (>= (window-sizable window delta horizontal ignore) delta)
    (<= (window-sizable window delta horizontal ignore) delta)))

(defun window-size-fixed-1 (window horizontal)
  "Internal function for `window-size-fixed-p'."
  (let ((sub (window-child window)))
    (catch 'fixed
      (if sub
	  ;; WINDOW is an internal window.
	  (if (window-iso-combined-p sub horizontal)
	      ;; An iso-combination is fixed size if all its subwindows
	      ;; are fixed-size.
	      (progn
		(while sub
		  (unless (window-size-fixed-1 sub horizontal)
		    ;; We found a non-fixed-size subwindow, so WINDOW's
		    ;; size is not fixed.
		    (throw 'fixed nil))
		  (setq sub (window-right sub)))
		;; All subwindows are fixed-size, so WINDOW's size is
		;; fixed.
		(throw 'fixed t))
	    ;; An ortho-combination is fixed-size if at least one of its
	    ;; subwindows is fixed-size.
	    (while sub
	      (when (window-size-fixed-1 sub horizontal)
		;; We found a fixed-size subwindow, so WINDOW's size is
		;; fixed.
		(throw 'fixed t))
	      (setq sub (window-right sub))))
	;; WINDOW is a live window.
	(with-current-buffer (window-buffer window)
	  (if horizontal
	      (memq window-size-fixed '(width t))
	    (memq window-size-fixed '(height t))))))))

(defun window-size-fixed-p (&optional window horizontal)
  "Return non-nil if WINDOW's height is fixed.
WINDOW can be an arbitrary window and defaults to the selected
window.  Optional argument HORIZONTAL non-nil means return
non-nil if WINDOW's width is fixed.

If this function returns nil, this does not necessarily mean that
WINDOW can be resized in the desired direction.  The functions
`window-resizable' and `window-resizable-p' will tell that."
  (window-size-fixed-1
   (normalize-any-window window) horizontal))

(defun window-min-delta-1 (window delta &optional horizontal ignore trail noup)
  "Internal function for `window-min-delta'."
  (if (not (window-parent window))
      ;; If we can't go up, return zero.
      0
    ;; Else try to find a non-fixed-size sibling of WINDOW.
    (let* ((parent (window-parent window))
	   (sub (window-child parent)))
      (catch 'done
	(if (window-iso-combined-p sub horizontal)
	    ;; In an iso-combination throw DELTA if we find at least one
	    ;; subwindow and that subwindow is either not of fixed-size
	    ;; or we can ignore fixed-sizeness.
	    (let ((skip (eq trail 'after)))
	      (while sub
		(cond
		 ((eq sub window)
		  (setq skip (eq trail 'before)))
		 (skip)
		 ((and (not (window-size-ignore window ignore))
		       (window-size-fixed-p sub horizontal)))
		 (t
		  ;; We found a non-fixed-size subwindow.
		  (throw 'done delta)))
		(setq sub (window-right sub))))
	  ;; In an ortho-combination set DELTA to the minimum value by
	  ;; which other subwindows can shrink.
	  (while sub
	    (unless (eq sub window)
	      (setq delta
		    (min delta
			 (- (window-total-size sub horizontal)
			    (window-min-size sub horizontal ignore)))))
	    (setq sub (window-right sub))))
	(if noup
	    delta
	  (window-min-delta-1 parent delta horizontal ignore trail))))))

(defun window-min-delta (&optional window horizontal ignore trail noup nodown)
  "Return number of lines by which WINDOW can be shrunk.
WINDOW can be an arbitrary window and defaults to the selected
window.  Return zero if WINDOW cannot be shrunk.

Optional argument HORIZONTAL non-nil means return number of
columns by which WINDOW can be shrunk.

Optional argument IGNORE non-nil means ignore any restrictions
imposed by fixed size windows, `window-min-height' or
`window-min-width' settings.  IGNORE a window means ignore
restrictions for that window only.  IGNORE equal `safe' means
live windows may get as small as `window-safe-min-height' lines
and `window-safe-min-width' columns.

Optional argument TRAIL `before' means only windows to the left
of or above WINDOW can be enlarged.  Optional argument TRAIL
`after' means only windows to the right of or below WINDOW can be
enlarged.

Optional argument NOUP non-nil means don't go up in the window
tree but try to enlarge windows within WINDOW's combination only.

Optional argument NODOWN non-nil means don't check whether WINDOW
itself \(and its subwindows) can be shrunk; check only whether at
least one other windows can be enlarged appropriately."
  (setq window (normalize-any-window window))
  (let ((size (window-total-size window horizontal))
	(minimum (window-min-size window horizontal ignore)))
    (cond
     (nodown
      ;; If NODOWN is t, try to recover the entire size of WINDOW.
      (window-min-delta-1 window size horizontal ignore trail noup))
     ((= size minimum)
      ;; If NODOWN is nil and WINDOW's size is already at its minimum,
      ;; there's nothing to recover.
      0)
     (t
      ;; Otherwise, try to recover whatever WINDOW is larger than its
      ;; minimum size.
      (window-min-delta-1
       window (- size minimum) horizontal ignore trail noup)))))

(defun window-max-delta-1 (window delta &optional horizontal ignore trail noup)
  "Internal function of `window-max-delta'."
  (if (not (window-parent window))
      ;; Can't go up.  Return DELTA.
      delta
    (let* ((parent (window-parent window))
	   (sub (window-child parent)))
      (catch 'fixed
	(if (window-iso-combined-p sub horizontal)
	    ;; For an iso-combination calculate how much we can get from
	    ;; other subwindows.
	    (let ((skip (eq trail 'after)))
	      (while sub
		(cond
		 ((eq sub window)
		  (setq skip (eq trail 'before)))
		 (skip)
		 (t
		  (setq delta
			(+ delta
			   (- (window-total-size sub horizontal)
			      (window-min-size sub horizontal ignore))))))
		(setq sub (window-right sub))))
	  ;; For an ortho-combination throw DELTA when at least one
	  ;; subwindow is fixed-size.
	  (while sub
	    (when (and (not (eq sub window))
		       (not (window-size-ignore sub ignore))
		       (window-size-fixed-p sub horizontal))
	      (throw 'fixed delta))
	    (setq sub (window-right sub))))
	(if noup
	    ;; When NOUP is nil, DELTA is all we can get.
	    delta
	  ;; Else try with parent of WINDOW, passing the DELTA we
	  ;; recovered so far.
	  (window-max-delta-1 parent delta horizontal ignore trail))))))

(defun window-max-delta (&optional window horizontal ignore trail noup nodown)
  "Return maximum number of lines WINDOW by which WINDOW can be enlarged.
WINDOW can be an arbitrary window and defaults to the selected
window.  The return value is zero if WINDOW cannot be enlarged.

Optional argument HORIZONTAL non-nil means return maximum number
of columns by which WINDOW can be enlarged.

Optional argument IGNORE non-nil means ignore any restrictions
imposed by fixed size windows, `window-min-height' or
`window-min-width' settings.  IGNORE a window means ignore
restrictions for that window only.  IGNORE equal `safe' means
live windows may get as small as `window-safe-min-height' lines
and `window-safe-min-width' columns.

Optional argument TRAIL `before' means only windows to the left
of or below WINDOW can be shrunk.  Optional argument TRAIL
`after' means only windows to the right of or above WINDOW can be
shrunk.

Optional argument NOUP non-nil means don't go up in the window
tree but try to obtain the entire space from windows within
WINDOW's combination.

Optional argument NODOWN non-nil means do not check whether
WINDOW itself \(and its subwindows) can be enlarged; check only
whether other windows can be shrunk appropriately."
  (setq window (normalize-any-window window))
  (if (and (not (window-size-ignore window ignore))
	   (not nodown) (window-size-fixed-p window horizontal))
      ;; With IGNORE and NOWDON nil return zero if WINDOW has fixed
      ;; size.
      0
    ;; WINDOW has no fixed size.
    (window-max-delta-1 window 0 horizontal ignore trail noup)))

;; Make NOUP also inhibit the min-size check.
(defun window-resizable (window delta &optional horizontal ignore trail noup nodown)
  "Return DELTA if WINDOW can be resized vertically by DELTA lines.
Optional argument HORIZONTAL non-nil means return DELTA if WINDOW
can be resized horizontally by DELTA columns.  A return value of
zero means that WINDOW is not resizable.

DELTA positive means WINDOW shall be enlarged by DELTA lines or
columns.  If WINDOW cannot be enlarged by DELTA lines or columns
return the maximum value in the range 0..DELTA by which WINDOW
can be enlarged.

DELTA negative means WINDOW shall be shrunk by -DELTA lines or
columns.  If WINDOW cannot be shrunk by -DELTA lines or columns,
return the minimum value in the range DELTA..0 that can be used
for shrinking WINDOW.

Optional argument IGNORE non-nil means ignore any restrictions
imposed by fixed size windows, `window-min-height' or
`window-min-width' settings.  IGNORE a window means ignore
restrictions for that window only.  IGNORE equal `safe' means
live windows may get as small as `window-safe-min-height' lines
and `window-safe-min-width' columns.

Optional argument TRAIL `before' means only windows to the left
of or below WINDOW can be shrunk.  Optional argument TRAIL
`after' means only windows to the right of or above WINDOW can be
shrunk.

Optional argument NOUP non-nil means don't go up in the window
tree but try to distribute the space among the other windows
within WINDOW's combination.

Optional argument NODOWN non-nil means don't check whether WINDOW
and its subwindows can be resized."
  (setq window (normalize-any-window window))
  (cond
   ((< delta 0)
    (max (- (window-min-delta window horizontal ignore trail noup nodown))
	 delta))
   ((> delta 0)
    (min (window-max-delta window horizontal ignore trail noup nodown)
	 delta))
   (t 0)))

(defun window-resizable-p (window delta &optional horizontal ignore trail noup nodown)
  "Return t if WINDOW can be resized vertically by DELTA lines.
For the meaning of the arguments of this function see the
doc-string of `window-resizable'."
  (setq window (normalize-any-window window))
  (if (> delta 0)
      (>= (window-resizable window delta horizontal ignore trail noup nodown)
	  delta)
    (<= (window-resizable window delta horizontal ignore trail noup nodown)
	delta)))

(defsubst window-total-height (&optional window)
  "Return the total number of lines of WINDOW.
WINDOW can be any window and defaults to the selected one.  The
return value includes WINDOW's mode line and header line, if any.
If WINDOW is internal the return value is the sum of the total
number of lines of WINDOW's child windows if these are vertically
combined and the height of WINDOW's first child otherwise.

Note: This function does not take into account the value of
`line-spacing' when calculating the number of lines in WINDOW."
  (window-total-size window))

;; Eventually we should make `window-height' obsolete.
(defalias 'window-height 'window-total-height)

;; See discussion in bug#4543.
(defsubst window-full-height-p (&optional window)
  "Return t if WINDOW is as high as the containing frame.
More precisely, return t if and only if the total height of
WINDOW equals the total height of the root window of WINDOW's
frame.  WINDOW can be any window and defaults to the selected
one."
  (setq window (normalize-any-window window))
  (= (window-total-size window)
     (window-total-size (frame-root-window window))))

(defsubst window-total-width (&optional window)
  "Return the total number of columns of WINDOW.
WINDOW can be any window and defaults to the selected one.  The
return value includes any vertical dividers or scrollbars of
WINDOW.  If WINDOW is internal, the return value is the sum of
the total number of columns of WINDOW's child windows if these
are horizontally combined and the width of WINDOW's first child
otherwise."
  (window-total-size window t))

(defsubst window-full-width-p (&optional window)
  "Return t if WINDOW is as wide as the containing frame.
More precisely, return t if and only if the total width of WINDOW
equals the total width of the root window of WINDOW's frame.
WINDOW can be any window and defaults to the selected one."
  (setq window (normalize-any-window window))
  (= (window-total-size window t)
     (window-total-size (frame-root-window window) t)))

(defsubst window-body-height (&optional window)
  "Return the number of lines of WINDOW's body.
WINDOW must be a live window and defaults to the selected one.

The return value does not include WINDOW's mode line and header
line, if any.  If a line at the bottom of the window is only
partially visible, that line is included in the return value.  If
you do not want to include a partially visible bottom line in the
return value, use `window-text-height' instead."
  (window-body-size window))

(defsubst window-body-width (&optional window)
  "Return the number of columns of WINDOW's body.
WINDOW must be a live window and defaults to the selected one.

The return value does not include any vertical dividers or scroll
bars owned by WINDOW.  On a window-system the return value does
not include the number of columns used for WINDOW's fringes or
display margins either."
  (window-body-size window t))

;; Eventually we should make `window-height' obsolete.
(defalias 'window-width 'window-body-width)

(defun window-current-scroll-bars (&optional window)
  "Return the current scroll bar settings for WINDOW.
WINDOW must be a live window and defaults to the selected one.

The return value is a cons cell (VERTICAL . HORIZONTAL) where
VERTICAL specifies the current location of the vertical scroll
bars (`left', `right', or nil), and HORIZONTAL specifies the
current location of the horizontal scroll bars (`top', `bottom',
or nil).

Unlike `window-scroll-bars', this function reports the scroll bar
type actually used, once frame defaults and `scroll-bar-mode' are
taken into account."
  (setq window (normalize-live-window window))
  (let ((vert (nth 2 (window-scroll-bars window)))
	(hor nil))
    (when (or (eq vert t) (eq hor t))
      (let ((fcsb (frame-current-scroll-bars (window-frame window))))
	(if (eq vert t)
	    (setq vert (car fcsb)))
	(if (eq hor t)
	    (setq hor (cdr fcsb)))))
    (cons vert hor)))

(defun walk-windows (proc &optional minibuf all-frames)
  "Cycle through all live windows, calling PROC for each one.
PROC must specify a function with a window as its sole argument.
The optional arguments MINIBUF and ALL-FRAMES specify the set of
windows to include in the walk.

MINIBUF t means include the minibuffer window even if the
minibuffer is not active.  MINIBUF nil or omitted means include
the minibuffer window only if the minibuffer is active.  Any
other value means do not include the minibuffer window even if
the minibuffer is active.

ALL-FRAMES nil or omitted means consider all windows on the
selected frame, plus the minibuffer window if specified by the
MINIBUF argument.  If the minibuffer counts, consider all windows
on all frames that share that minibuffer too.  The following
non-nil values of ALL-FRAMES have special meanings:

- t means consider all windows on all existing frames.

- `visible' means consider all windows on all visible frames on
  the current terminal.

- 0 (the number zero) means consider all windows on all visible
  and iconified frames on the current terminal.

- A frame means consider all windows on that frame only.

Anything else means consider all windows on the selected frame
and no others.

This function changes neither the order of recently selected
windows nor the buffer list."
  ;; If we start from the minibuffer window, don't fail to come
  ;; back to it.
  (when (window-minibuffer-p (selected-window))
    (setq minibuf t))
  ;; Make sure to not mess up the order of recently selected
  ;; windows.  Use `save-selected-window' and `select-window'
  ;; with second argument non-nil for this purpose.
  (save-selected-window
    (when (framep all-frames)
      (select-window (frame-first-window all-frames) 'norecord))
    (dolist (walk-windows-window (window-list-1 nil minibuf all-frames))
      (funcall proc walk-windows-window))))

(defun window-in-direction-2 (window posn &optional horizontal)
  "Support function for `window-in-direction'."
  (if horizontal
      (let ((top (window-top-line window)))
	(if (> top posn)
	    (- top posn)
	  (- posn top (window-total-height window))))
    (let ((left (window-left-column window)))
      (if (> left posn)
	  (- left posn)
	(- posn left (window-total-width window))))))

(defun window-in-direction (direction &optional window ignore)
  "Return window in DIRECTION as seen from WINDOW.
DIRECTION must be one of `above', `below', `left' or `right'.
WINDOW must be a live window and defaults to the selected one.
IGNORE, when non-nil means a window can be returned even if its
`no-other-window' parameter is non-nil."
  (setq window (normalize-live-window window))
  (unless (memq direction '(above below left right))
    (error "Wrong direction %s" direction))
  (let* ((frame (window-frame window))
	 (hor (memq direction '(left right)))
	 (first (if hor
		    (window-left-column window)
		  (window-top-line window)))
	 (last (+ first (if hor
			    (window-total-width window)
			  (window-total-height window))))
	 (posn-cons (nth 6 (posn-at-point (window-point window) window)))
	 ;; The column / row value of `posn-at-point' can be nil for the
	 ;; mini-window, guard against that.
	 (posn (if hor
		   (+ (or (cdr posn-cons) 1) (window-top-line window))
		 (+ (or (car posn-cons) 1) (window-left-column window))))
	 (best-edge
	  (cond
	   ((eq direction 'below) (frame-height frame))
	   ((eq direction 'right) (frame-width frame))
	   (t -1)))
	 (best-edge-2 best-edge)
	 (best-diff-2 (if hor (frame-height frame) (frame-width frame)))
	 best best-2 best-diff-2-new)
    (walk-window-tree
     (lambda (w)
       (let* ((w-top (window-top-line w))
	      (w-left (window-left-column w)))
	 (cond
	  ((or (eq window w)
	       ;; Ignore ourselves.
	       (and (window-parameter w 'no-other-window)
		    ;; Ignore W unless IGNORE is non-nil.
		    (not ignore))))
	  (hor
	   (cond
	    ((and (<= w-top posn)
		  (< posn (+ w-top (window-total-height w))))
	     ;; W is to the left or right of WINDOW and covers POSN.
	     (when (or (and (eq direction 'left)
			    (<= w-left first) (> w-left best-edge))
		       (and (eq direction 'right)
			    (>= w-left last) (< w-left best-edge)))
	       (setq best-edge w-left)
	       (setq best w)))
	    ((and (or (and (eq direction 'left)
			   (<= (+ w-left (window-total-width w)) first))
		      (and (eq direction 'right) (<= last w-left)))
		  ;; W is to the left or right of WINDOW but does not
		  ;; cover POSN.
		  (setq best-diff-2-new
			(window-in-direction-2 w posn hor))
		  (or (< best-diff-2-new best-diff-2)
		      (and (= best-diff-2-new best-diff-2)
			   (if (eq direction 'left)
			       (> w-left best-edge-2)
			     (< w-left best-edge-2)))))
	     (setq best-edge-2 w-left)
	     (setq best-diff-2 best-diff-2-new)
	     (setq best-2 w))))
	  (t
	   (cond
	    ((and (<= w-left posn)
		  (< posn (+ w-left (window-total-width w))))
	     ;; W is above or below WINDOW and covers POSN.
	     (when (or (and (eq direction 'above)
			    (<= w-top first) (> w-top best-edge))
		       (and (eq direction 'below)
			    (>= w-top first) (< w-top best-edge)))
	       (setq best-edge w-top)
	       (setq best w)))
	    ((and (or (and (eq direction 'above)
			   (<= (+ w-top (window-total-height w)) first))
		      (and (eq direction 'below) (<= last w-top)))
		  ;; W is above or below WINDOW but does not cover POSN.
		  (setq best-diff-2-new
			(window-in-direction-2 w posn hor))
		  (or (< best-diff-2-new best-diff-2)
		      (and (= best-diff-2-new best-diff-2)
			   (if (eq direction 'above)
			       (> w-top best-edge-2)
			     (< w-top best-edge-2)))))
	     (setq best-edge-2 w-top)
	     (setq best-diff-2 best-diff-2-new)
	     (setq best-2 w)))))))
     (window-frame window))
    (or best best-2)))

(defun get-window-with-predicate (predicate &optional minibuf all-frames default)
  "Return a live window satisfying PREDICATE.
More precisely, cycle through all windows calling the function
PREDICATE on each one of them with the window as its sole
argument.  Return the first window for which PREDICATE returns
non-nil.  Windows are scanned starting with the window following
the selcted window.  If no window satisfies PREDICATE, return
DEFAULT.

MINIBUF t means include the minibuffer window even if the
minibuffer is not active.  MINIBUF nil or omitted means include
the minibuffer window only if the minibuffer is active.  Any
other value means do not include the minibuffer window even if
the minibuffer is active.

ALL-FRAMES nil or omitted means consider all windows on the selected
frame, plus the minibuffer window if specified by the MINIBUF
argument.  If the minibuffer counts, consider all windows on all
frames that share that minibuffer too.  The following non-nil
values of ALL-FRAMES have special meanings:

- t means consider all windows on all existing frames.

- `visible' means consider all windows on all visible frames on
  the current terminal.

- 0 (the number zero) means consider all windows on all visible
  and iconified frames on the current terminal.

- A frame means consider all windows on that frame only.

Anything else means consider all windows on the selected frame
and no others."
  (catch 'found
    (dolist (window (window-list-1
		     (next-window nil minibuf all-frames)
		     minibuf all-frames))
      (when (funcall predicate window)
	(throw 'found window)))
    default))

(defalias 'some-window 'get-window-with-predicate)

(defun get-lru-window (&optional all-frames dedicated)
   "Return the least recently used window on frames specified by ALL-FRAMES.
Return a full-width window if possible.  A minibuffer window is
never a candidate.  A dedicated window is never a candidate
unless DEDICATED is non-nil, so if all windows are dedicated, the
value is nil.  Avoid returning the selected window if possible.

The following non-nil values of the optional argument ALL-FRAMES
have special meanings:

- t means consider all windows on all existing frames.

- `visible' means consider all windows on all visible frames on
  the current terminal.

- 0 (the number zero) means consider all windows on all visible
  and iconified frames on the current terminal.

- A frame means consider all windows on that frame only.

Any other value of ALL-FRAMES means consider all windows on the
selected frame and no others."
   (let (best-window best-time second-best-window second-best-time time)
    (dolist (window (window-list-1 nil nil all-frames))
      (when (or dedicated (not (window-dedicated-p window)))
	(setq time (window-use-time window))
	(if (or (eq window (selected-window))
		(not (window-full-width-p window)))
	    (when (or (not second-best-time) (< time second-best-time))
	      (setq second-best-time time)
	      (setq second-best-window window))
	  (when (or (not best-time) (< time best-time))
	    (setq best-time time)
	    (setq best-window window)))))
    (or best-window second-best-window)))

(defun get-mru-window (&optional all-frames)
   "Return the most recently used window on frames specified by ALL-FRAMES.
Do not return a minibuffer window.

The following non-nil values of the optional argument ALL-FRAMES
have special meanings:

- t means consider all windows on all existing frames.

- `visible' means consider all windows on all visible frames on
  the current terminal.

- 0 (the number zero) means consider all windows on all visible
  and iconified frames on the current terminal.

- A frame means consider all windows on that frame only.

Any other value of ALL-FRAMES means consider all windows on the
selected frame and no others."
   (let (best-window best-time time)
    (dolist (window (window-list-1 nil nil all-frames))
      (setq time (window-use-time window))
      (when (or (not best-time) (> time best-time))
	(setq best-time time)
	(setq best-window window)))
    best-window))

(defun get-largest-window (&optional all-frames dedicated)
  "Return the largest window on frames specified by ALL-FRAMES.
A minibuffer window is never a candidate.  A dedicated window is
never a candidate unless DEDICATED is non-nil, so if all windows
are dedicated, the value is nil.

The following non-nil values of the optional argument ALL-FRAMES
have special meanings:

- t means consider all windows on all existing frames.

- `visible' means consider all windows on all visible frames on
  the current terminal.

- 0 (the number zero) means consider all windows on all visible
  and iconified frames on the current terminal.

- A frame means consider all windows on that frame only.

Any other value of ALL-FRAMES means consider all windows on the
selected frame and no others."
  (let ((best-size 0)
	best-window size)
    (dolist (window (window-list-1 nil nil all-frames))
      (when (or dedicated (not (window-dedicated-p window)))
	(setq size (* (window-total-size window)
		      (window-total-size window t)))
	(when (> size best-size)
	  (setq best-size size)
	  (setq best-window window))))
    best-window))

(defun get-buffer-window-list (&optional buffer-or-name minibuf all-frames)
  "Return list of all windows displaying BUFFER-OR-NAME, or nil if none.
BUFFER-OR-NAME may be a buffer or the name of an existing buffer
and defaults to the current buffer.  Windows are scanned starting
with the selected window.

MINIBUF t means include the minibuffer window even if the
minibuffer is not active.  MINIBUF nil or omitted means include
the minibuffer window only if the minibuffer is active.  Any
other value means do not include the minibuffer window even if
the minibuffer is active.

ALL-FRAMES nil or omitted means consider all windows on the
selected frame, plus the minibuffer window if specified by the
MINIBUF argument.  If the minibuffer counts, consider all windows
on all frames that share that minibuffer too.  The following
non-nil values of ALL-FRAMES have special meanings:

- t means consider all windows on all existing frames.

- `visible' means consider all windows on all visible frames on
  the current terminal.

- 0 (the number zero) means consider all windows on all visible
  and iconified frames on the current terminal.

- A frame means consider all windows on that frame only.

Anything else means consider all windows on the selected frame
and no others."
  (let ((buffer (normalize-live-buffer buffer-or-name))
	windows)
    (dolist (window (window-list-1 (selected-window) minibuf all-frames))
      (when (eq (window-buffer window) buffer)
	(setq windows (cons window windows))))
    (nreverse windows)))

(defun minibuffer-window-active-p (window)
  "Return t if WINDOW is the currently active minibuffer window."
  (eq window (active-minibuffer-window)))

(defun count-windows (&optional minibuf)
   "Return the number of live windows on the selected frame.
The optional argument MINIBUF specifies whether the minibuffer
window shall be counted.  See `walk-windows' for the precise
meaning of this argument."
   (length (window-list-1 nil minibuf)))

;;; Resizing windows.
(defun resize-window-reset (&optional frame horizontal)
  "Reset resize values for all windows on FRAME.
FRAME defaults to the selected frame.

This function stores the current value of `window-total-size' applied
with argument HORIZONTAL in the new total size of all windows on
FRAME.  It also resets the new normal size of each of these
windows."
  (resize-window-reset-1
   (frame-root-window (normalize-live-frame frame)) horizontal))

(defun resize-window-reset-1 (window horizontal)
  "Internal function of `resize-window-reset'."
  ;; Register old size in the new total size.
  (set-window-new-total window (window-total-size window horizontal))
  ;; Reset new normal size.
  (set-window-new-normal window)
  (when (window-child window)
    (resize-window-reset-1 (window-child window) horizontal))
  (when (window-right window)
    (resize-window-reset-1 (window-right window) horizontal)))

;; The following routine is used to manually resize the minibuffer
;; window and is currently used, for example, by ispell.el.
(defun resize-mini-window (window delta)
  "Resize minibuffer window WINDOW by DELTA lines.
If WINDOW cannot be resized by DELTA lines make it as large \(or
as small) as possible but don't signal an error."
  (when (window-minibuffer-p window)
    (let* ((frame (window-frame window))
	   (root (frame-root-window frame))
	   (height (window-total-size window))
	   (min-delta
	    (- (window-total-size root)
	       (window-min-size root))))
      ;; Sanitize DELTA.
      (cond
       ((<= (+ height delta) 0)
	(setq delta (- (- height 1))))
       ((> delta min-delta)
	(setq delta min-delta)))

      ;; Resize now.
      (resize-window-reset frame)
      ;; Ideally we should be able to resize just the last subwindow of
      ;; root here.  See the comment in `resize-root-window-vertically'
      ;; for why we do not do that.
      (resize-this-window root (- delta) nil nil t)
      (set-window-new-total window (+ height delta))
      ;; The following routine catches the case where we want to resize
      ;; a minibuffer-only frame.
      (resize-mini-window-internal window))))

(defun resize-window (window delta &optional horizontal ignore)
  "Resize WINDOW vertically by DELTA lines.
WINDOW can be an arbitrary window and defaults to the selected
one.  An attempt to resize the root window of a frame will raise
an error though.

DELTA a positive number means WINDOW shall be enlarged by DELTA
lines.  DELTA negative means WINDOW shall be shrunk by -DELTA
lines.

Optional argument HORIZONTAL non-nil means resize WINDOW
horizontally by DELTA columns.  In this case a positive DELTA
means enlarge WINDOW by DELTA columns.  DELTA negative means
WINDOW shall be shrunk by -DELTA columns.

Optional argument IGNORE non-nil means ignore any restrictions
imposed by fixed size windows, `window-min-height' or
`window-min-width' settings.  IGNORE any window means ignore
restrictions for that window only.  IGNORE equal `safe' means
live windows may get as small as `window-safe-min-height' lines
and `window-safe-min-width' columns.

This function resizes other windows proportionally and never
deletes any windows.  If you want to move only the low (right)
edge of WINDOW consider using `adjust-window-trailing-edge'
instead."
  (setq window (normalize-any-window window))
  (let* ((frame (window-frame window))
	 sibling)
    (cond
     ((eq window (frame-root-window frame))
      (error "Cannot resize the root window of a frame"))
     ((window-minibuffer-p window)
      (resize-mini-window window delta))
     ((window-resizable-p window delta horizontal ignore)
      (resize-window-reset frame horizontal)
      (resize-this-window window delta horizontal ignore t)
      (if (and (not (window-splits window))
	       (window-iso-combined-p window horizontal)
	       (setq sibling (or (window-right window) (window-left window)))
	       (window-sizable-p sibling (- delta) horizontal ignore))
	  ;; If window-splits returns nil for WINDOW, WINDOW is part of
	  ;; an iso-combination, and WINDOW's neighboring right or left
	  ;; sibling can be resized as requested, resize that sibling.
	  (let ((normal-delta
		 (/ (float delta)
		    (window-total-size (window-parent window) horizontal))))
	    (resize-this-window sibling (- delta) horizontal nil t)
	    (set-window-new-normal
	     window (+ (window-normal-size window horizontal)
		       normal-delta))
	    (set-window-new-normal
	     sibling (- (window-normal-size sibling horizontal)
			normal-delta)))
	;; Otherwise, resize all other windows in the same combination.
	(resize-other-windows window delta horizontal ignore))
      (resize-window-apply frame horizontal))
     (t
      (error "Cannot resize window %s" window)))))

(defsubst resize-subwindows-skip-p (window)
  "Return non-nil if WINDOW shall be skipped by resizing routines."
  (memq (window-new-normal window) '(ignore stuck skip)))

(defun resize-subwindows-normal (parent horizontal window this-delta &optional trail other-delta)
  "Set the new normal height of subwindows of window PARENT.
HORIZONTAL non-nil means set the new normal width of these
windows.  WINDOW specifies a subwindow of PARENT that has been
resized by THIS-DELTA lines \(columns).

Optional argument TRAIL either 'before or 'after means set values
for windows before or after WINDOW only.  Optional argument
OTHER-DELTA a number specifies that this many lines \(columns)
have been obtained from \(or returned to) an ancestor window of
PARENT in order to resize WINDOW."
  (let* ((delta-normal
	  (if (and (= (- this-delta) (window-total-size window horizontal))
		   (zerop other-delta))
	      ;; When WINDOW gets deleted and we can return its entire
	      ;; space to its siblings, use WINDOW's normal size as the
	      ;; normal delta.
	      (- (window-normal-size window horizontal))
	    ;; In any other case calculate the normal delta from the
	    ;; relation of THIS-DELTA to the total size of PARENT.
	    (/ (float this-delta) (window-total-size parent horizontal))))
	 (sub (window-child parent))
	 (parent-normal 0.0)
	 (skip (eq trail 'after)))

    ;; Set parent-normal to the sum of the normal sizes of all
    ;; subwindows of PARENT that shall be resized, excluding only WINDOW
    ;; and any windows specified by the optional TRAIL argument.
    (while sub
      (cond
       ((eq sub window)
	(setq skip (eq trail 'before)))
       (skip)
       (t
	(setq parent-normal
	      (+ parent-normal (window-normal-size sub horizontal)))))
      (setq sub (window-right sub)))

    ;; Set the new normal size of all subwindows of PARENT from what
    ;; they should have contributed for recovering THIS-DELTA lines
    ;; (columns).
    (setq sub (window-child parent))
    (setq skip (eq trail 'after))
    (while sub
      (cond
       ((eq sub window)
	(setq skip (eq trail 'before)))
       (skip)
       (t
	(let ((old-normal (window-normal-size sub horizontal)))
	  (set-window-new-normal
	   sub (min 1.0 ; Don't get larger than 1.
		    (max (- old-normal
			    (* (/ old-normal parent-normal)
			       delta-normal))
			 ;; Don't drop below 0.
			 0.0))))))
      (setq sub (window-right sub)))

    (when (numberp other-delta)
      ;; Set the new normal size of windows from what they should have
      ;; contributed for recovering OTHER-DELTA lines (columns).
      (setq delta-normal (/ (float (window-total-size parent horizontal))
			    (+ (window-total-size parent horizontal)
			       other-delta)))
      (setq sub (window-child parent))
      (setq skip (eq trail 'after))
      (while sub
	(cond
	 ((eq sub window)
	  (setq skip (eq trail 'before)))
	 (skip)
	 (t
	  (set-window-new-normal
	   sub (min 1.0 ; Don't get larger than 1.
		    (max (* (window-new-normal sub) delta-normal)
			 ;; Don't drop below 0.
			 0.0)))))
	(setq sub (window-right sub))))

    ;; Set the new normal size of WINDOW to what is left by the sum of
    ;; the normal sizes of its siblings.
    (set-window-new-normal
     window
     (let ((sum 0))
       (setq sub (window-child parent))
       (while sub
	 (cond
	  ((eq sub window))
	  ((not (numberp (window-new-normal sub)))
	   (setq sum (+ sum (window-normal-size sub horizontal))))
	  (t
	   (setq sum (+ sum (window-new-normal sub)))))
	 (setq sub (window-right sub)))
       ;; Don't get larger than 1 or smaller than 0.
       (min 1.0 (max (- 1.0 sum) 0.0))))))

(defun resize-subwindows (parent delta &optional horizontal window ignore trail edge)
  "Resize subwindows of window PARENT vertically by DELTA lines.
PARENT must be a vertically combined internal window.

Optional argument HORIZONTAL non-nil means resize subwindows of
PARENT horizontally by DELTA columns.  In this case PARENT must
be a horizontally combined internal window.

WINDOW, if specified, must denote a child window of PARENT that
is resized by DELTA lines.

Optional argument IGNORE non-nil means ignore any restrictions
imposed by fixed size windows, `window-min-height' or
`window-min-width' settings.  IGNORE equal `safe' means live
windows may get as small as `window-safe-min-height' lines and
`window-safe-min-width' columns.  IGNORE any window means ignore
restrictions for that window only.

Optional arguments TRAIL and EDGE, when non-nil, restrict the set
of windows that shall be resized.  If TRAIL equals `before',
resize only windows on the left or above EDGE.  If TRAIL equals
`after', resize only windows on the right or below EDGE.  Also,
preferably only resize windows adjacent to EDGE.

Return the symbol `normalized' if new normal sizes have been
already set by this routine."
  (let* ((first (window-child parent))
	 (sub first)
	 (parent-total (+ (window-total-size parent horizontal) delta))
	 best-window best-value)

    (if (and edge (memq trail '(before after))
	     (progn
	       (setq sub first)
	       (while (and (window-right sub)
			   (or (and (eq trail 'before)
				    (not (resize-subwindows-skip-p
					  (window-right sub))))
			       (and (eq trail 'after)
				    (resize-subwindows-skip-p sub))))
		 (setq sub (window-right sub)))
	       sub)
	     (if horizontal
		 (if (eq trail 'before)
		     (= (+ (window-left-column sub)
			   (window-total-size sub t))
			edge)
		   (= (window-left-column sub) edge))
	       (if (eq trail 'before)
		   (= (+ (window-top-line sub)
			 (window-total-size sub))
		      edge)
		 (= (window-top-line sub) edge)))
	     (window-sizable-p sub delta horizontal ignore))
	;; Resize only windows adjacent to EDGE.
	(progn
	  (resize-this-window sub delta horizontal ignore t trail edge)
	  (if (and window (eq (window-parent sub) parent))
	      (progn
		;; Assign new normal sizes.
		(set-window-new-normal
		 sub (/ (float (window-new-total sub)) parent-total))
		(set-window-new-normal
		 window (- (window-normal-size window horizontal)
			   (- (window-new-normal sub)
			      (window-normal-size sub horizontal)))))
	    (resize-subwindows-normal parent horizontal sub 0 trail delta))
	  ;; Return 'normalized to notify `resize-other-windows' that
	  ;; normal sizes have been already set.
	  'normalized)
      ;; Resize all windows proportionally.
      (setq sub first)
      (while sub
	(cond
	 ((or (resize-subwindows-skip-p sub)
	      ;; Ignore windows to skip and fixed-size subwindows - in
	      ;; the latter case make it a window to skip.
	      (and (not ignore)
		   (window-size-fixed-p sub horizontal)
		   (set-window-new-normal sub 'ignore))))
	 ((< delta 0)
	  ;; When shrinking store the number of lines/cols we can get
	  ;; from this window here together with the total/normal size
	  ;; factor.
	  (set-window-new-normal
	   sub
	   (cons
	    ;; We used to call this with NODOWN t, "fixed" 2011-05-11.
	    (window-min-delta sub horizontal ignore trail t) ; t)
	    (- (/ (float (window-total-size sub horizontal))
		  parent-total)
	       (window-normal-size sub horizontal)))))
	 ((> delta 0)
	  ;; When enlarging store the total/normal size factor only
	  (set-window-new-normal
	   sub
	   (- (/ (float (window-total-size sub horizontal))
		 parent-total)
	      (window-normal-size sub horizontal)))))

	(setq sub (window-right sub)))

      (cond
       ((< delta 0)
	;; Shrink windows by delta.
	(setq best-window t)
	(while (and best-window (not (zerop delta)))
	  (setq sub first)
	  (setq best-window nil)
	  (setq best-value most-negative-fixnum)
	  (while sub
	    (when (and (consp (window-new-normal sub))
		       (not (zerop (car (window-new-normal sub))))
		       (> (cdr (window-new-normal sub)) best-value))
	      (setq best-window sub)
	      (setq best-value (cdr (window-new-normal sub))))

	    (setq sub (window-right sub)))

	  (when best-window
	    (setq delta (1+ delta)))
	  (set-window-new-total best-window -1 t)
	  (set-window-new-normal
	   best-window
	   (if (= (car (window-new-normal best-window)) 1)
	       'skip ; We can't shrink best-window any further.
	     (cons (1- (car (window-new-normal best-window)))
		   (- (/ (float (window-new-total best-window))
			 parent-total)
		      (window-normal-size best-window horizontal)))))))
       ((> delta 0)
	;; Enlarge windows by delta.
	(setq best-window t)
	(while (and best-window (not (zerop delta)))
	  (setq sub first)
	  (setq best-window nil)
	  (setq best-value most-positive-fixnum)
	  (while sub
	    (when (and (numberp (window-new-normal sub))
		       (< (window-new-normal sub) best-value))
	      (setq best-window sub)
	      (setq best-value (window-new-normal sub)))

	    (setq sub (window-right sub)))

	  (when best-window
	    (setq delta (1- delta)))
	  (set-window-new-total best-window 1 t)
	  (set-window-new-normal
	   best-window
	   (- (/ (float (window-new-total best-window))
		 parent-total)
	      (window-normal-size best-window horizontal))))))

      (when best-window
	(setq sub first)
	(while sub
	  (when (or (consp (window-new-normal sub))
		    (numberp (window-new-normal sub)))
	    ;; Reset new normal size fields so `resize-window-apply'
	    ;; won't use them to apply new sizes.
	    (set-window-new-normal sub))

	  (unless (eq (window-new-normal sub) 'ignore)
	    ;; Resize this subwindow's subwindows (back-engineering
	    ;; delta from sub's old and new total sizes).
	    (let ((delta (- (window-new-total sub)
			    (window-total-size sub horizontal))))
	      (unless (and (zerop delta) (not trail))
		;; For the TRAIL non-nil case we have to resize SUB
		;; recursively even if it's size does not change.
		(resize-this-window
		 sub delta horizontal ignore nil trail edge))))
	  (setq sub (window-right sub)))))))

(defun resize-other-windows (window delta &optional horizontal ignore trail edge)
  "Resize other windows when WINDOW is resized vertically by DELTA lines.
Optional argument HORIZONTAL non-nil means resize other windows
when WINDOW is resized horizontally by DELTA columns.  WINDOW
itself is not resized by this function.

Optional argument IGNORE non-nil means ignore any restrictions
imposed by fixed size windows, `window-min-height' or
`window-min-width' settings.  IGNORE equal `safe' means live
windows may get as small as `window-safe-min-height' lines and
`window-safe-min-width' columns.  IGNORE any window means ignore
restrictions for that window only.

Optional arguments TRAIL and EDGE, when non-nil, refine the set
of windows that shall be resized.  If TRAIL equals `before',
resize only windows on the left or above EDGE.  If TRAIL equals
`after', resize only windows on the right or below EDGE.  Also,
preferably only resize windows adjacent to EDGE."
  (when (window-parent window)
    (let* ((parent (window-parent window))
	   (sub (window-child parent)))
      (if (window-iso-combined-p sub horizontal)
	  ;; In an iso-combination try to extract DELTA from WINDOW's
	  ;; siblings.
	  (let ((first sub)
		(skip (eq trail 'after))
		this-delta other-delta)
	    ;; Decide which windows shall be left alone.
	    (while sub
	      (cond
	       ((eq sub window)
		;; Make sure WINDOW is left alone when
		;; resizing its siblings.
		(set-window-new-normal sub 'ignore)
		(setq skip (eq trail 'before)))
	       (skip
		;; Make sure this sibling is left alone when
		;; resizing its siblings.
		(set-window-new-normal sub 'ignore))
	       ((or (window-size-ignore sub ignore)
		    (not (window-size-fixed-p sub horizontal)))
		;; Set this-delta to t to signal that we found a sibling
		;; of WINDOW whose size is not fixed.
		(setq this-delta t)))

	      (setq sub (window-right sub)))

	    ;; Set this-delta to what we can get from WINDOW's siblings.
	    (if (= (- delta) (window-total-size window horizontal))
		;; A deletion, presumably.  We must handle this case
		;; specially since `window-resizable' can't be used.
		(if this-delta
		    ;; There's at least one resizable sibling we can
		    ;; give WINDOW's size to.
		    (setq this-delta delta)
		  ;; No resizable sibling exists.
		  (setq this-delta 0))
	      ;; Any other form of resizing.
	      (setq this-delta
		    (window-resizable window delta horizontal ignore trail t)))

	    ;; Set other-delta to what we still have to get from
	    ;; ancestor windows of parent.
	    (setq other-delta (- delta this-delta))
	    (unless (zerop other-delta)
	      ;; Unless we got everything from WINDOW's siblings, PARENT
	      ;; must be resized by other-delta lines or columns.
	      (set-window-new-total parent other-delta 'add))

	    (if (zerop this-delta)
		;; We haven't got anything from WINDOW's siblings but we
		;; must update the normal sizes to respect other-delta.
		(resize-subwindows-normal
		 parent horizontal window this-delta trail other-delta)
	      ;; We did get something from WINDOW's siblings which means
	      ;; we have to resize their subwindows.
	      (unless (eq (resize-subwindows parent (- this-delta) horizontal
					     window ignore trail edge)
			  ;; `resize-subwindows' returning 'normalized,
			  ;; means it has set the normal sizes already.
			  'normalized)
		;; Set the normal sizes.
		(resize-subwindows-normal
		 parent horizontal window this-delta trail other-delta))
	      ;; Set DELTA to what we still have to get from ancestor
	      ;; windows.
	      (setq delta other-delta)))

	;; In an ortho-combination all siblings of WINDOW must be
	;; resized by DELTA.
	(set-window-new-total parent delta 'add)
	(while sub
	  (unless (eq sub window)
	    (resize-this-window sub delta horizontal ignore t))
	  (setq sub (window-right sub))))

      (unless (zerop delta)
	;; "Go up."
	(resize-other-windows parent delta horizontal ignore trail edge)))))

(defun resize-this-window (window delta &optional horizontal ignore add trail edge)
  "Resize WINDOW vertically by DELTA lines.
Optional argument HORIZONTAL non-nil means resize WINDOW
horizontally by DELTA columns.

Optional argument IGNORE non-nil means ignore any restrictions
imposed by fixed size windows, `window-min-height' or
`window-min-width' settings.  IGNORE equal `safe' means live
windows may get as small as `window-safe-min-height' lines and
`window-safe-min-width' columns.  IGNORE any window means ignore
restrictions for that window only.

Optional argument ADD non-nil means add DELTA to the new total
size of WINDOW.

Optional arguments TRAIL and EDGE, when non-nil, refine the set
of windows that shall be resized.  If TRAIL equals `before',
resize only windows on the left or above EDGE.  If TRAIL equals
`after', resize only windows on the right or below EDGE.  Also,
preferably only resize windows adjacent to EDGE.

This function recursively resizes WINDOW's subwindows to fit the
new size.  Make sure that WINDOW is `window-resizable' before
calling this function.  Note that this function does not resize
siblings of WINDOW or WINDOW's parent window.  You have to
eventually call `resize-window-apply' in order to make resizing
actually take effect."
  (when add
    ;; Add DELTA to the new total size of WINDOW.
    (set-window-new-total window delta t))

  (let ((sub (window-child window)))
    (cond
     ((not sub))
     ((window-iso-combined-p sub horizontal)
      ;; In an iso-combination resize subwindows according to their
      ;; normal sizes.
      (resize-subwindows window delta horizontal nil ignore trail edge))
     ;; In an ortho-combination resize each subwindow by DELTA.
     (t
      (while sub
	(resize-this-window sub delta horizontal ignore t trail edge)
	(setq sub (window-right sub)))))))

(defun resize-root-window (window delta horizontal ignore)
  "Resize root window WINDOW vertically by DELTA lines.
HORIZONTAL non-nil means resize root window WINDOW horizontally
by DELTA columns.

IGNORE non-nil means ignore any restrictions imposed by fixed
size windows, `window-min-height' or `window-min-width' settings.

This function is only called by the frame resizing routines.  It
resizes windows proportionally and never deletes any windows."
  (when (and (windowp window) (numberp delta)
	     (window-sizable-p window delta horizontal ignore))
    (resize-window-reset (window-frame window) horizontal)
    (resize-this-window window delta horizontal ignore t)))

(defun resize-root-window-vertically (window delta)
  "Resize root window WINDOW vertically by DELTA lines.
If DELTA is less than zero and we can't shrink WINDOW by DELTA
lines, shrink it as much as possible.  If DELTA is greater than
zero, this function can resize fixed-size subwindows in order to
recover the necessary lines.

Return the number of lines that were recovered.

This function is only called by the minibuffer window resizing
routines.  It resizes windows proportionally and never deletes
any windows."
  (when (numberp delta)
    (let (ignore)
      (cond
       ((< delta 0)
	(setq delta (window-sizable window delta)))
       ((> delta 0)
	(unless (window-sizable window delta)
	  (setq ignore t))))

      (resize-window-reset (window-frame window))
      ;; Ideally, we would resize just the last window in a combination
      ;; but that's not feasible for the following reason: If we grow
      ;; the minibuffer window and the last window cannot be shrunk any
      ;; more, we shrink another window instead.  But if we then shrink
      ;; the minibuffer window again, the last window might get enlarged
      ;; and the state after shrinking is not the state before growing.
      ;; So, in practice, we'd need a history variable to record how to
      ;; proceed.  But I'm not sure how such a variable could work with
      ;; repeated minibuffer window growing steps.
      (resize-this-window window delta nil ignore t)
      delta)))

(defun adjust-window-trailing-edge (window delta &optional horizontal)
  "Move WINDOW's bottom edge by DELTA lines.
Optional argument HORIZONTAL non-nil means move WINDOW's right
edge by DELTA columns.  WINDOW defaults to the selected window.

If DELTA is greater zero, then move the edge downwards or to the
right.  If DELTA is less than zero, move the edge upwards or to
the left.  If the edge can't be moved by DELTA lines or columns,
move it as far as possible in the desired direction."
  (setq window (normalize-any-window window))
  (let ((frame (window-frame window))
	(right window)
	left this-delta min-delta max-delta failed)
    ;; Find the edge we want to move.
    (while (and (or (not (window-iso-combined-p right horizontal))
		    (not (window-right right)))
		(setq right (window-parent right))))
    (cond
     ((and (not right) (not horizontal) (not resize-mini-windows)
	   (eq (window-frame (minibuffer-window frame)) frame))
      (resize-mini-window (minibuffer-window frame) (- delta)))
     ((or (not (setq left right)) (not (setq right (window-right right))))
      (if horizontal
	  (error "No window on the right of this one")
	(error "No window below this one")))
     (t
      ;; Set LEFT to the first resizable window on the left.  This step is
      ;; needed to handle fixed-size windows.
      (while (and left (window-size-fixed-p left horizontal))
	(setq left
	      (or (window-left left)
		  (progn
		    (while (and (setq left (window-parent left))
				(not (window-iso-combined-p left horizontal))))
		    (window-left left)))))
      (unless left
	(if horizontal
	    (error "No resizable window on the left of this one")
	  (error "No resizable window above this one")))

      ;; Set RIGHT to the first resizable window on the right.  This step
      ;; is needed to handle fixed-size windows.
      (while (and right (window-size-fixed-p right horizontal))
	(setq right
	      (or (window-right right)
		  (progn
		    (while (and (setq right (window-parent right))
				(not (window-iso-combined-p right horizontal))))
		    (window-right right)))))
      (unless right
	(if horizontal
	    (error "No resizable window on the right of this one")
	  (error "No resizable window below this one")))

      ;; LEFT and RIGHT (which might be both internal windows) are now the
      ;; two windows we want to resize.
      (cond
       ((> delta 0)
	(setq max-delta (window-max-delta-1 left 0 horizontal nil 'after))
	(setq min-delta (window-min-delta-1 right (- delta) horizontal nil 'before))
	(when (or (< max-delta delta) (> min-delta (- delta)))
	  ;; We can't get the whole DELTA - move as far as possible.
	  (setq delta (min max-delta (- min-delta))))
	(unless (zerop delta)
	  ;; Start resizing.
	  (resize-window-reset frame horizontal)
	  ;; Try to enlarge LEFT first.
	  (setq this-delta (window-resizable left delta horizontal))
	  (unless (zerop this-delta)
	    (resize-this-window
	     left this-delta horizontal nil t 'before
	     (if horizontal
		 (+ (window-left-column left) (window-total-size left t))
	       (+ (window-top-line left) (window-total-size left)))))
	  ;; Shrink windows on right of LEFT.
	  (resize-other-windows
	   left delta horizontal nil 'after
	   (if horizontal
	       (window-left-column right)
	     (window-top-line right)))))
       ((< delta 0)
	(setq max-delta (window-max-delta-1 right 0 horizontal nil 'before))
	(setq min-delta (window-min-delta-1 left delta horizontal nil 'after))
	(when (or (< max-delta (- delta)) (> min-delta delta))
	  ;; We can't get the whole DELTA - move as far as possible.
	  (setq delta (max (- max-delta) min-delta)))
	(unless (zerop delta)
	  ;; Start resizing.
	  (resize-window-reset frame horizontal)
	  ;; Try to enlarge RIGHT.
	  (setq this-delta (window-resizable right (- delta) horizontal))
	  (unless (zerop this-delta)
	    (resize-this-window
	     right this-delta horizontal nil t 'after
	     (if horizontal
		 (window-left-column right)
	       (window-top-line right))))
	  ;; Shrink windows on left of RIGHT.
	  (resize-other-windows
	   right (- delta) horizontal nil 'before
	   (if horizontal
	       (+ (window-left-column left) (window-total-size left t))
	     (+ (window-top-line left) (window-total-size left)))))))
      (unless (zerop delta)
	;; Don't report an error in the standard case.
	(unless (resize-window-apply frame horizontal)
	  ;; But do report an error if applying the changes fails.
	  (error "Failed adjusting window %s" window)))))))

(defun enlarge-window (delta &optional horizontal)
  "Make selected window DELTA lines taller.
Interactively, if no argument is given, make the selected window
one line taller.  If optional argument HORIZONTAL is non-nil,
make selected window wider by DELTA columns.  If DELTA is
negative, shrink selected window by -DELTA lines or columns.
Return nil."
  (interactive "p")
  (cond
   ((zerop delta))
   ((window-size-fixed-p nil horizontal)
    (error "Selected window has fixed size"))
   ((window-resizable-p nil delta horizontal)
    (resize-window nil delta horizontal))
   (t
    (resize-window
     nil (if (> delta 0)
	     (window-max-delta nil horizontal)
	   (- (window-min-delta nil horizontal)))
     horizontal))))

(defun shrink-window (delta &optional horizontal)
  "Make selected window DELTA lines smaller.
Interactively, if no argument is given, make the selected window
one line smaller.  If optional argument HORIZONTAL is non-nil,
make selected window narrower by DELTA columns.  If DELTA is
negative, enlarge selected window by -DELTA lines or columns.
Return nil."
  (interactive "p")
  (cond
   ((zerop delta))
   ((window-size-fixed-p nil horizontal)
    (error "Selected window has fixed size"))
   ((window-resizable-p nil (- delta) horizontal)
    (resize-window nil (- delta) horizontal))
   (t
    (resize-window
     nil (if (> delta 0)
	     (- (window-min-delta nil horizontal))
	   (window-max-delta nil horizontal))
     horizontal))))

(defun maximize-window (&optional window)
  "Maximize WINDOW.
Make WINDOW as large as possible without deleting any windows.
WINDOW can be any window and defaults to the selected window."
  (interactive)
  (setq window (normalize-any-window window))
  (resize-window window (window-max-delta window))
  (resize-window window (window-max-delta window t) t))

(defun minimize-window (&optional window)
  "Minimize WINDOW.
Make WINDOW as small as possible without deleting any windows.
WINDOW can be any window and defaults to the selected window."
  (interactive)
  (setq window (normalize-any-window window))
  (resize-window window (- (window-min-delta window)))
  (resize-window window (- (window-min-delta window t)) t))

(defsubst frame-root-window-p (window)
  "Return non-nil if WINDOW is the root window of its frame."
  (eq window (frame-root-window window)))

(defun window-tree-1 (window &optional next)
  "Return window tree rooted at WINDOW.
Optional argument NEXT non-nil means include windows right
siblings in the return value.

See the documentation of `window-tree' for a description of the
return value."
  (let (list)
    (while window
      (setq list
	    (cons
	     (cond
	      ((window-vchild window)
	       (cons t (cons (window-edges window)
			     (window-tree-1 (window-vchild window) t))))
	      ((window-hchild window)
	       (cons nil (cons (window-edges window)
			       (window-tree-1 (window-hchild window) t))))
	      (t window))
	     list))
      (setq window (when next (window-next window))))
    (nreverse list)))

(defun window-tree (&optional frame)
  "Return the window tree of frame FRAME.
FRAME must be a live frame and defaults to the selected frame.
The return value is a list of the form (ROOT MINI), where ROOT
represents the window tree of the frame's root window, and MINI
is the frame's minibuffer window.

If the root window is not split, ROOT is the root window itself.
Otherwise, ROOT is a list (DIR EDGES W1 W2 ...) where DIR is nil
for a horizontal split, and t for a vertical split.  EDGES gives
the combined size and position of the subwindows in the split,
and the rest of the elements are the subwindows in the split.
Each of the subwindows may again be a window or a list
representing a window split, and so on.  EDGES is a list \(LEFT
TOP RIGHT BOTTOM) as returned by `window-edges'."
  (setq frame (normalize-live-frame frame))
  (window-tree-1 (frame-root-window frame) t))

(defun other-window (count &optional all-frames)
  "Select another window in cyclic ordering of windows.
COUNT specifies the number of windows to skip, starting with the
selected window, before making the selection.  If COUNT is
positive, skip COUNT windows forwards.  If COUNT is negative,
skip -COUNT windows backwards.  COUNT zero means do not skip any
window, so select the selected window.  In an interactive call,
COUNT is the numeric prefix argument.  Return nil.

If the `other-window' parameter of WINDOW is a function and
`ignore-window-parameters' is nil, call that function with the
arguments COUNT and ALL-FRAMES.

This function does not select a window whose `no-other-window'
window parameter is non-nil.

This function uses `next-window' for finding the window to
select.  The argument ALL-FRAMES has the same meaning as in
`next-window', but the MINIBUF argument of `next-window' is
always effectively nil."
  (interactive "p")
  (let* ((window (selected-window))
	 (function (and (not ignore-window-parameters)
			(window-parameter window 'other-window)))
	 old-window old-count)
    (if (functionp function)
	(funcall function count all-frames)
      ;; `next-window' and `previous-window' may return a window we are
      ;; not allowed to select.  Hence we need an exit strategy in case
      ;; all windows are non-selectable.
      (catch 'exit
	(while (> count 0)
	  (setq window (next-window window nil all-frames))
	  (cond
	   ((eq window old-window)
	    (when (= count old-count)
	      ;; Keep out of infinite loops.  When COUNT has not changed
	      ;; since we last looked at `window' we're probably in one.
	      (throw 'exit nil)))
	   ((window-parameter window 'no-other-window)
	    (unless old-window
	      ;; The first non-selectable window `next-window' got us:
	      ;; Remember it and the current value of COUNT.
	      (setq old-window window)
	      (setq old-count count)))
	   (t
	    (setq count (1- count)))))
	(while (< count 0)
	  (setq window (previous-window window nil all-frames))
	  (cond
	   ((eq window old-window)
	    (when (= count old-count)
	      ;; Keep out of infinite loops.  When COUNT has not changed
	      ;; since we last looked at `window' we're probably in one.
	      (throw 'exit nil)))
	   ((window-parameter window 'no-other-window)
	    (unless old-window
	      ;; The first non-selectable window `previous-window' got
	      ;; us: Remember it and the current value of COUNT.
	      (setq old-window window)
	      (setq old-count count)))
	   (t
	    (setq count (1+ count)))))

	(select-window window)
	;; Always return nil.
	nil))))

;; This should probably return non-nil when the selected window is part
;; of an atomic window whose root is the frame's root window.
(defun one-window-p (&optional nomini all-frames)
  "Return non-nil if the selected window is the only window.
Optional arg NOMINI non-nil means don't count the minibuffer
even if it is active.  Otherwise, the minibuffer is counted
when it is active.

Optional argument ALL-FRAMES specifies the set of frames to
consider, see also `next-window'.  ALL-FRAMES nil or omitted
means consider windows on the selected frame only, plus the
minibuffer window if specified by the NOMINI argument.  If the
minibuffer counts, consider all windows on all frames that share
that minibuffer too.  The remaining non-nil values of ALL-FRAMES
with a special meaning are:

- t means consider all windows on all existing frames.

- `visible' means consider all windows on all visible frames on
  the current terminal.

- 0 (the number zero) means consider all windows on all visible
  and iconified frames on the current terminal.

- A frame means consider all windows on that frame only.

Anything else means consider all windows on the selected frame
and no others."
  (let ((base-window (selected-window)))
    (if (and nomini (eq base-window (minibuffer-window)))
	(setq base-window (next-window base-window)))
    (eq base-window
	(next-window base-window (if nomini 'arg) all-frames))))

;;; Deleting windows.
(defcustom frame-auto-delete 'automatic
  "If non-nil, quitting a window can delete it's frame.
If this variable is nil, functions that quit a window never
delete the associated frame.  If this variable equals the symbol
`automatic', a frame is deleted only if it the window is
dedicated or was created by `display-buffer'.  If this variable
is t, a frame can be always deleted, even if it was created by
`make-frame-command'.  Other values should not be used.

Note that a frame will be effectively deleted if and only if
another frame still exists.

Functions quitting a window and consequently affected by this
variable are `switch-to-prev-buffer', `delete-windows-on',
`replace-buffer-in-windows' and `quit-restore-window'."
  :type '(choice
	  (const :tag "Never" nil)
	  (const :tag "Automatic" automatic)
	  (const :tag "Always" t))
  :group 'windows
  :group 'frames)

(defun window-deletable-p (&optional window)
  "Return t if WINDOW can be safely deleted from its frame.
Return `frame' if deleting WINDOW should delete its frame
instead."
  (setq window (normalize-any-window window))
  (unless ignore-window-parameters
    ;; Handle atomicity.
    (when (window-parameter window 'window-atom)
      (setq window (window-atom-root window))))
  (let ((parent (window-parent window))
	(frame (window-frame window))
	(dedicated (and (window-buffer window) (window-dedicated-p window)))
	(quit-restore (window-parameter window 'quit-restore)))
    (cond
     ((frame-root-window-p window)
      (when (and (or (eq frame-auto-delete t)
		     (and (eq frame-auto-delete 'automatic)
			  (or dedicated
			      (and (eq (car-safe quit-restore) 'new-frame)
				   (eq (nth 1 quit-restore)
				       (window-buffer window))))))
		 (other-visible-frames-p frame))
	;; WINDOW is the root window of its frame.  Return `frame' but
	;; only if WINDOW is (1) either dedicated or quit-restore's car
	;; is new-frame and the window still displays the same buffer
	;; and (2) there are other frames left.
	'frame))
     ((and (not ignore-window-parameters)
	   (eq (window-parameter window 'window-side) 'none)
	   (or (not parent)
	       (not (eq (window-parameter parent 'window-side) 'none))))
      ;; Can't delete last main window.
      nil)
     (t))))

(defun window-or-subwindow-p (subwindow window)
  "Return t if SUBWINDOW is either WINDOW or a subwindow of WINDOW."
  (or (eq subwindow window)
      (let ((parent (window-parent subwindow)))
	(catch 'done
	  (while parent
	    (if (eq parent window)
		(throw 'done t)
	      (setq parent (window-parent parent))))))))

(defun delete-window (&optional window)
  "Delete WINDOW.
WINDOW can be an arbitrary window and defaults to the selected
one.  Return nil.

If the variable `ignore-window-parameters' is non-nil or the
`delete-window' parameter of WINDOW equals t, do not process any
parameters of WINDOW.  Otherwise, if the `delete-window'
parameter of WINDOW specifies a function, call that function with
WINDOW as its sole argument and return the value returned by that
function.

Otherwise, if WINDOW is part of an atomic window, call
`delete-window' with the root of the atomic window as its
argument.  If WINDOW is the only window on its frame or the last
non-side window, signal an error."
  (interactive)
  (setq window (normalize-any-window window))
  (let* ((frame (window-frame window))
	 (function (window-parameter window 'delete-window))
	 (parent (window-parent window))
	 atom-root)
    (window-check frame)
    (catch 'done
      ;; Handle window parameters.
      (cond
       ;; Ignore window parameters if `ignore-window-parameters' tells
       ;; us so or `delete-window' equals t.
       ((or ignore-window-parameters (eq function t)))
       ((functionp function)
	;; The `delete-window' parameter specifies the function to call.
	;; If that function is `ignore' nothing is done.  It's up to the
	;; function called here to avoid infinite recursion.
	(throw 'done (funcall function window)))
       ((and (window-parameter window 'window-atom)
	     (setq atom-root (window-atom-root window))
	     (not (eq atom-root window)))
	(throw 'done (delete-window atom-root)))
       ((and (eq (window-parameter window 'window-side) 'none)
	     (or (not parent)
		 (not (eq (window-parameter parent 'window-side) 'none))))
	(error "Attempt to delete last non-side window"))
       ((not parent)
	(error "Attempt to delete minibuffer or sole ordinary window")))

      (let* ((horizontal (window-hchild parent))
	     (size (window-total-size window horizontal))
	     (frame-selected
	      (window-or-subwindow-p (frame-selected-window frame) window))
	     ;; Emacs 23 preferably gives WINDOW's space to its left
	     ;; sibling.
	     (sibling (or (window-left window) (window-right window))))
	(resize-window-reset frame horizontal)
	(cond
	 ((and (not (window-splits window))
	       sibling (window-sizable-p sibling size))
	  ;; Resize WINDOW's sibling.
	  (resize-this-window sibling size horizontal nil t)
	  (set-window-new-normal
	   sibling (+ (window-normal-size sibling horizontal)
		      (window-normal-size window horizontal))))
	 ((window-resizable-p window (- size) horizontal nil nil nil t)
	  ;; Can do without resizing fixed-size windows.
	  (resize-other-windows window (- size) horizontal))
	 (t
	  ;; Can't do without resizing fixed-size windows.
	  (resize-other-windows window (- size) horizontal t)))
	;; Actually delete WINDOW.
	(delete-window-internal window)
	(when (and frame-selected
		   (window-parameter
		    (frame-selected-window frame) 'no-other-window))
	  ;; `delete-window-internal' has selected a window that should
	  ;; not be selected, fix this here.
	  (other-window -1 frame))
	(run-window-configuration-change-hook frame)
	(window-check frame)
	;; Always return nil.
	nil))))

(defun delete-other-windows (&optional window)
  "Make WINDOW fill its frame.
WINDOW may be any window and defaults to the selected one.
Return nil.

If the variable `ignore-window-parameters' is non-nil or the
`delete-other-windows' parameter of WINDOW equals t, do not
process any parameters of WINDOW.  Otherwise, if the
`delete-other-windows' parameter of WINDOW specifies a function,
call that function with WINDOW as its sole argument and return
the value returned by that function.

Otherwise, if WINDOW is part of an atomic window, call this
function with the root of the atomic window as its argument.  If
WINDOW is a non-side window, make WINDOW the only non-side window
on the frame.  Side windows are not deleted. If WINDOW is a side
window signal an error."
  (interactive)
  (setq window (normalize-any-window window))
  (let* ((frame (window-frame window))
	 (function (window-parameter window 'delete-other-windows))
	 (window-side (window-parameter window 'window-side))
	 atom-root side-main)
    (window-check frame)
    (catch 'done
      (cond
       ;; Ignore window parameters if `ignore-window-parameters' is t or
       ;; `delete-other-windows' is t.
       ((or ignore-window-parameters (eq function t)))
       ((functionp function)
	;; The `delete-other-windows' parameter specifies the function
	;; to call.  If the function is `ignore' no windows are deleted.
	;; It's up to the function called to avoid infinite recursion.
	(throw 'done (funcall function window)))
       ((and (window-parameter window 'window-atom)
	     (setq atom-root (window-atom-root window))
	     (not (eq atom-root window)))
	(throw 'done (delete-other-windows atom-root)))
       ((eq window-side 'none)
	;; Set side-main to the major non-side window.
	(setq side-main (window-with-parameter 'window-side 'none nil t)))
       ((memq window-side window-sides)
	(error "Cannot make side window the only window")))
      ;; If WINDOW is the main non-side window, do nothing.
      (unless (eq window side-main)
	(delete-other-windows-internal window side-main)
	(run-window-configuration-change-hook frame)
	(window-check frame))
      ;; Always return nil.
      nil)))

(defun delete-other-windows-vertically (&optional window)
  "Delete the windows in the same column with WINDOW, but not WINDOW itself.
This may be a useful alternative binding for \\[delete-other-windows]
 if you often split windows horizontally."
  (interactive)
  (let* ((window (or window (selected-window)))
         (edges (window-edges window))
         (w window) delenda)
    (while (not (eq (setq w (next-window w 1)) window))
      (let ((e (window-edges w)))
        (when (and (= (car e) (car edges))
                   (= (caddr e) (caddr edges)))
          (push w delenda))))
    (mapc 'delete-window delenda)))

;;; Windows and buffers.

;; `prev-buffers' and `next-buffers' are two reserved window slots used
;; for (1) determining which buffer to show in the window when its
;; buffer shall be buried or killed and (2) which buffer to show for
;; `switch-to-prev-buffer' and `switch-to-next-buffer'.

;; `prev-buffers' consists of <buffer, window-start, window-point>
;; triples.  The entries on this list are ordered by the time their
;; buffer has been removed from the window, the most recently removed
;; buffer's entry being first.  The window-start and window-point
;; components are `window-start' and `window-point' at the time the
;; buffer was removed from the window which implies that the entry must
;; be added when `set-window-buffer' removes the buffer from the window.

;; `next-buffers' is the list of buffers that have been replaced
;; recently by `switch-to-prev-buffer'.  These buffers are the least
;; preferred candidates of `switch-to-prev-buffer' and the preferred
;; candidates of `switch-to-next-buffer' to switch to.  This list is
;; reset to nil by any action changing the window's buffer with the
;; exception of `switch-to-prev-buffer' and `switch-to-next-buffer'.
;; `switch-to-prev-buffer' pushes the buffer it just replaced on it,
;; `switch-to-next-buffer' pops the last pushed buffer from it.

;; Both `prev-buffers' and `next-buffers' may reference killed buffers
;; if such a buffer was killed while the window was hidden within a
;; window configuration.  Such killed buffers get removed whenever
;; `switch-to-prev-buffer' or `switch-to-next-buffer' encounter them.

;; The following function is called by `set-window-buffer' _before_ it
;; replaces the buffer of the argument window with the new buffer.
(defun record-window-buffer (&optional window)
  "Record WINDOW's buffer.
WINDOW must be a live window and defaults to the selected one."
  (let* ((window (normalize-live-window window))
	 (buffer (window-buffer window))
	 (entry (assq buffer (window-prev-buffers window))))
    ;; Reset WINDOW's next buffers.  If needed, they are resurrected by
    ;; `switch-to-prev-buffer' and `switch-to-next-buffer'.
    (set-window-next-buffers window nil)

    (when entry
      ;; Remove all entries for BUFFER from WINDOW's previous buffers.
      (set-window-prev-buffers
       window (assq-delete-all buffer (window-prev-buffers window))))

    ;; Don't record insignificant buffers.
    (unless (eq (aref (buffer-name buffer) 0) ?\s)
      ;; Add an entry for buffer to WINDOW's previous buffers.
      (with-current-buffer buffer
	(let ((start (window-start window))
	      (point (window-point window)))
	  (setq entry
		(cons buffer
		      (if entry
			  ;; We have an entry, update marker positions.
			  (list (set-marker (nth 1 entry) start)
				(set-marker (nth 2 entry) point))
			;; Make new markers.
			(list (copy-marker start)
			      (copy-marker point)))))

	  (set-window-prev-buffers
	   window (cons entry (window-prev-buffers window))))))))

(defun unrecord-window-buffer (&optional window buffer)
  "Unrecord BUFFER in WINDOW.
WINDOW must be a live window and defaults to the selected one.
BUFFER must be a live buffer and defaults to the buffer of
WINDOW."
  (let* ((window (normalize-live-window window))
	 (buffer (or buffer (window-buffer window))))
    (set-window-prev-buffers
     window (assq-delete-all buffer (window-prev-buffers window)))
    (set-window-next-buffers
     window (delq buffer (window-next-buffers window)))))

(defun set-window-buffer-start-and-point (window buffer &optional start point)
  "Set WINDOW's buffer to BUFFER.
Optional argument START non-nil means set WINDOW's start position
to START.  Optional argument POINT non-nil means set WINDOW's
point to POINT.  If WINDOW is selected this also sets BUFFER's
`point' to POINT.  If WINDOW is selected and the buffer it showed
before was current this also makes BUFFER the current buffer."
  (let ((selected (eq window (selected-window)))
	(current (eq (window-buffer window) (current-buffer))))
    (set-window-buffer window buffer)
    (when (and selected current)
      (set-buffer buffer))
    (when start
      (set-window-start window start))
    (when point
      (if selected
	  (with-current-buffer buffer
	    (goto-char point))
	(set-window-point window point)))))

(defun switch-to-prev-buffer (&optional window bury-or-kill)
  "In WINDOW switch to previous buffer.
WINDOW must be a live window and defaults to the selected one.

Optional argument BURY-OR-KILL non-nil means the buffer currently
shown in WINDOW is about to be buried or killed and consequently
shall not be switched to in future invocations of this command."
  (interactive)
  (let* ((window (normalize-live-window window))
	 (old-buffer (window-buffer window))
	 ;; Save this since it's destroyed by `set-window-buffer'.
	 (next-buffers (window-next-buffers window))
	 entry new-buffer killed-buffers deletable visible)
    (cond
     ;; When BURY-OR-KILL is non-nil, there's no previous buffer for
     ;; this window, and we can delete the window (or the frame) do
     ;; that.
     ((and bury-or-kill
	   (or (not (window-prev-buffers window))
	       (and (eq (caar (window-prev-buffers window)) old-buffer)
		    (not (cdr (car (window-prev-buffers window))))))
	   (setq deletable (window-deletable-p window)))
      (if (eq deletable 'frame)
	  (delete-frame (window-frame window))
	(delete-window window)))
     ((window-dedicated-p window)
      (error "Window %s is dedicated to buffer %s" window old-buffer)))

    (unless deletable
      (catch 'found
	;; Scan WINDOW's previous buffers first, skipping entries of next
	;; buffers.
	(dolist (entry (window-prev-buffers window))
	  (when (and (setq new-buffer (car entry))
		     (or (buffer-live-p new-buffer)
			 (not (setq killed-buffers
				    (cons new-buffer killed-buffers))))
		     (not (eq new-buffer old-buffer))
		     (or bury-or-kill
			 (not (memq new-buffer next-buffers))))
	    (set-window-buffer-start-and-point
	     window new-buffer (nth 1 entry) (nth 2 entry))
	    (throw 'found t)))
	;; Scan reverted buffer list of WINDOW's frame next, skipping
	;; entries of next buffers.  Note that when we bury or kill a
	;; buffer we don't reverse the global buffer list to avoid showing
	;; a buried buffer instead.  Otherwise, we must reverse the global
	;; buffer list in order to make sure that switching to the
	;; previous/next buffer traverse it in opposite directions.
	(dolist (buffer (if bury-or-kill
			    (buffer-list (window-frame window))
			  (nreverse (buffer-list (window-frame window)))))
	  (when (and (buffer-live-p buffer)
		     (not (eq buffer old-buffer))
		     (not (eq (aref (buffer-name buffer) 0) ?\s))
		     (or bury-or-kill (not (memq buffer next-buffers))))
	    (if (get-buffer-window buffer)
		;; Try to avoid showing a buffer visible in some other window.
		(setq visible buffer)
	    (setq new-buffer buffer)
	    (set-window-buffer-start-and-point window new-buffer)
	    (throw 'found t))))
	(unless bury-or-kill
	  ;; Scan reverted next buffers last (must not use nreverse
	  ;; here!).
	  (dolist (buffer (reverse next-buffers))
	    ;; Actually, buffer _must_ be live here since otherwise it
	    ;; would have been caught in the scan of previous buffers.
	    (when (and (or (buffer-live-p buffer)
			   (not (setq killed-buffers
				      (cons buffer killed-buffers))))
		       (not (eq buffer old-buffer))
		       (setq entry (assq buffer (window-prev-buffers window))))
	      (setq new-buffer buffer)
	      (set-window-buffer-start-and-point
	       window new-buffer (nth 1 entry) (nth 2 entry))
	      (throw 'found t))))

	;; Show a buffer visible in another window.
	(when visible
	  (setq new-buffer visible)
	  (set-window-buffer-start-and-point window new-buffer)))

      (if bury-or-kill
	  ;; Remove `old-buffer' from WINDOW's previous and (restored list
	  ;; of) next buffers.
	  (progn
	    (set-window-prev-buffers
	     window (assq-delete-all old-buffer (window-prev-buffers window)))
	    (set-window-next-buffers window (delq old-buffer next-buffers)))
	;; Move `old-buffer' to head of WINDOW's restored list of next
	;; buffers.
	(set-window-next-buffers
	 window (cons old-buffer (delq old-buffer next-buffers)))))

    ;; Remove killed buffers from WINDOW's previous and next buffers.
    (when killed-buffers
      (dolist (buffer killed-buffers)
	(set-window-prev-buffers
	 window (assq-delete-all buffer (window-prev-buffers window)))
	(set-window-next-buffers
	 window (delq buffer (window-next-buffers window)))))

    ;; Return new-buffer.
    new-buffer))

(defun switch-to-next-buffer (&optional window)
  "In WINDOW switch to next buffer.
WINDOW must be a live window and defaults to the selected one."
  (interactive)
  (let* ((window (normalize-live-window window))
	 (old-buffer (window-buffer window))
	 (next-buffers (window-next-buffers window))
	 new-buffer entry killed-buffers visible)
    (when (window-dedicated-p window)
      (error "Window %s is dedicated to buffer %s" window old-buffer))

    (catch 'found
      ;; Scan WINDOW's next buffers first.
      (dolist (buffer next-buffers)
	(when (and (or (buffer-live-p buffer)
		       (not (setq killed-buffers
				  (cons buffer killed-buffers))))
		   (not (eq buffer old-buffer))
		   (setq entry (assq buffer (window-prev-buffers window))))
	  (setq new-buffer buffer)
	  (set-window-buffer-start-and-point
	   window new-buffer (nth 1 entry) (nth 2 entry))
	  (throw 'found t)))
      ;; Scan the buffer list of WINDOW's frame next, skipping previous
      ;; buffers entries.
      (dolist (buffer (buffer-list (window-frame window)))
	(when (and (buffer-live-p buffer) (not (eq buffer old-buffer))
		   (not (eq (aref (buffer-name buffer) 0) ?\s))
		   (not (assq buffer (window-prev-buffers window))))
	  (if (get-buffer-window buffer)
	      ;; Try to avoid showing a buffer visible in some other window.
	      (setq visible buffer)
	    (setq new-buffer buffer)
	    (set-window-buffer-start-and-point window new-buffer)
	    (throw 'found t))))
      ;; Scan WINDOW's reverted previous buffers last (must not use
      ;; nreverse here!)
      (dolist (entry (reverse (window-prev-buffers window)))
	(when (and (setq new-buffer (car entry))
		   (or (buffer-live-p new-buffer)
		       (not (setq killed-buffers
				  (cons new-buffer killed-buffers))))
		   (not (eq new-buffer old-buffer)))
	  (set-window-buffer-start-and-point
	   window new-buffer (nth 1 entry) (nth 2 entry))
	  (throw 'found t)))

      ;; Show a buffer visible in another window.
      (when visible
	(setq new-buffer visible)
	(set-window-buffer-start-and-point window new-buffer)))

    ;; Remove `new-buffer' from and restore WINDOW's next buffers.
    (set-window-next-buffers window (delq new-buffer next-buffers))

    ;; Remove killed buffers from WINDOW's previous and next buffers.
    (when killed-buffers
      (dolist (buffer killed-buffers)
	(set-window-prev-buffers
	 window (assq-delete-all buffer (window-prev-buffers window)))
	(set-window-next-buffers
	 window (delq buffer (window-next-buffers window)))))

    ;; Return new-buffer.
    new-buffer))

(defun get-next-valid-buffer (list &optional buffer visible-ok frame)
  "Search LIST for a valid buffer to display in FRAME.
Return nil when all buffers in LIST are undesirable for display,
otherwise return the first suitable buffer in LIST.

Buffers not visible in windows are preferred to visible buffers,
unless VISIBLE-OK is non-nil.
If the optional argument FRAME is nil, it defaults to the selected frame.
If BUFFER is non-nil, ignore occurrences of that buffer in LIST."
  ;; This logic is more or less copied from other-buffer.
  (setq frame (or frame (selected-frame)))
  (let ((pred (frame-parameter frame 'buffer-predicate))
	found buf)
    (while (and (not found) list)
      (setq buf (car list))
      (if (and (not (eq buffer buf))
	       (buffer-live-p buf)
	       (or (null pred) (funcall pred buf))
	       (not (eq (aref (buffer-name buf) 0) ?\s))
	       (or visible-ok (null (get-buffer-window buf 'visible))))
	  (setq found buf)
	(setq list (cdr list))))
    (car list)))

(defun last-buffer (&optional buffer visible-ok frame)
  "Return the last buffer in FRAME's buffer list.
If BUFFER is the last buffer, return the preceding buffer
instead.  Buffers not visible in windows are preferred to visible
buffers, unless optional argument VISIBLE-OK is non-nil.
Optional third argument FRAME nil or omitted means use the
selected frame's buffer list.  If no such buffer exists, return
the buffer `*scratch*', creating it if necessary."
  (setq frame (or frame (selected-frame)))
  (or (get-next-valid-buffer (nreverse (buffer-list frame))
 			     buffer visible-ok frame)
      (get-buffer "*scratch*")
      (let ((scratch (get-buffer-create "*scratch*")))
	(set-buffer-major-mode scratch)
	scratch)))

(defun bury-buffer (&optional buffer-or-name)
  "Put BUFFER-OR-NAME at the end of the list of all buffers.
There it is the least likely candidate for `other-buffer' to
return; thus, the least likely buffer for \\[switch-to-buffer] to
select by default.

You can specify a buffer name as BUFFER-OR-NAME, or an actual
buffer object.  If BUFFER-OR-NAME is nil or omitted, bury the
current buffer.  Also, if BUFFER-OR-NAME is nil or omitted,
remove the current buffer from the selected window if it is
displayed there."
  (interactive)
  (let* ((buffer (normalize-live-buffer buffer-or-name)))
    ;; If `buffer-or-name' is not on the selected frame we unrecord it
    ;; although it's not "here" (call it a feature).
    (unrecord-buffer buffer)
    ;; Handle case where `buffer-or-name' is nil and the current buffer
    ;; is shown in the selected window.
    (cond
     ((or buffer-or-name (not (eq buffer (window-buffer)))))
     ((not (window-dedicated-p))
      (switch-to-prev-buffer nil 'bury))
     ((frame-root-window-p (selected-window))
      (iconify-frame (window-frame (selected-window))))
     ((window-deletable-p)
      (delete-window)))
    ;; Always return nil.
    nil))

(defun unbury-buffer ()
  "Switch to the last buffer in the buffer list."
  (interactive)
  (switch-to-buffer (last-buffer)))

(defun next-buffer ()
  "In selected window switch to next buffer."
  (interactive)
  (switch-to-next-buffer))

(defun previous-buffer ()
  "In selected window switch to previous buffer."
  (interactive)
  (switch-to-prev-buffer))

(defun delete-windows-on (&optional buffer-or-name frame)
  "Delete all windows showing BUFFER-OR-NAME.
BUFFER-OR-NAME may be a buffer or the name of an existing buffer
and defaults to the current buffer.

The following non-nil values of the optional argument FRAME
have special meanings:

- t means consider all windows on the selected frame only.

- `visible' means consider all windows on all visible frames on
  the current terminal.

- 0 (the number zero) means consider all windows on all visible
  and iconified frames on the current terminal.

- A frame means consider all windows on that frame only.

Any other value of FRAME means consider all windows on all
frames.

When a window showing BUFFER-OR-NAME is dedicated and the only
window of its frame, that frame is deleted when there are other
frames left."
  (interactive "BDelete windows on (buffer):\nP")
  (let ((buffer (normalize-live-buffer buffer-or-name))
	;; Handle the "inverted" meaning of the FRAME argument wrt other
	;; `window-list-1' based function.
	(all-frames (cond ((not frame) t) ((eq frame t) nil) (t frame))))
    (dolist (window (window-list-1 nil nil all-frames))
      (if (eq (window-buffer window) buffer)
	  (let ((deletable (window-deletable-p window)))
	    (cond
	     ((eq deletable 'frame)
	      ;; Delete frame.
	      (delete-frame (window-frame window)))
	     (deletable
	      ;; Delete window only.
	      (delete-window window))
	     (t
	      ;; In window switch to previous buffer.
	      (set-window-dedicated-p window nil)
	      (switch-to-prev-buffer window 'bury))))
	;; If a window doesn't show BUFFER, unrecord BUFFER in it.
	(unrecord-window-buffer window buffer)))))

(defun replace-buffer-in-windows (&optional buffer-or-name)
  "Replace BUFFER-OR-NAME with some other buffer in all windows showing it.
BUFFER-OR-NAME may be a buffer or the name of an existing buffer
and defaults to the current buffer.

When a window showing BUFFER-OR-NAME is either dedicated, or the
window has no previous buffer, that window is deleted.  If that
window is the only window on its frame, the frame is deleted too
when there are other frames left.  If there are no other frames
left, some other buffer is displayed in that window.

This function removes the buffer denoted by BUFFER-OR-NAME from
all window-local buffer lists."
  (let ((buffer (normalize-live-buffer buffer-or-name)))
    (dolist (window (window-list-1 nil nil t))
      (if (eq (window-buffer window) buffer)
	  (let ((deletable (window-deletable-p window)))
	    (cond
	     ((eq deletable 'frame)
	      ;; Delete frame.
	      (delete-frame (window-frame window)))
	     ((and (window-dedicated-p window) deletable)
	      ;; Delete window.
	      (delete-window window))
	     (t
	      ;; Switch to another buffer in window.
	      (set-window-dedicated-p window nil)
	      (switch-to-prev-buffer window 'kill))))
	;; Unrecord BUFFER in WINDOW.
	(unrecord-window-buffer window buffer)))))

(defun quit-restore-window (&optional window kill)
  "Quit WINDOW in some way.
WINDOW must be a live window and defaults to the selected window.
Return nil.

According to information stored in WINDOW's `quit-restore' window
parameter either \(1) delete WINDOW and its frame, \(2) delete
WINDOW, \(3) restore the buffer previously displayed in WINDOW,
or \(4) make WINDOW display some other buffer than the present
one.  If non-nil, reset `quit-restore' parameter to nil.

Optional argument KILL non-nil means in addition kill WINDOW's
buffer.  If KILL is nil, put WINDOW's buffer at the end of the
buffer list.  Interactively, KILL is the prefix argument."
  (interactive "i\nP")
  (setq window (normalize-live-window window))
  (let ((buffer (window-buffer window))
	(quit-restore (window-parameter window 'quit-restore))
	deletable resize)
    (cond
     ((and (or (and (memq (car-safe quit-restore) '(new-window new-frame))
		    ;; Check that WINDOW's buffer is still the same.
		    (eq (window-buffer window) (nth 1 quit-restore)))
	       (window-dedicated-p window))
	   (setq deletable (window-deletable-p window)))
      ;; WINDOW can be deleted.
      (unrecord-buffer buffer)
      (if (eq deletable 'frame)
	  ;; WINDOW's frame can be deleted.
	  (delete-frame (window-frame window))
	;; Just delete WINDOW.
	(delete-window window))
      ;; If the previously selected window is still alive, select it.
      (when (window-live-p (nth 2 quit-restore))
	(select-window (nth 2 quit-restore))))
     ((and (buffer-live-p (nth 0 quit-restore))
	   ;; The buffer currently shown in WINDOW must still be the
	   ;; buffer shown when its `quit-restore' parameter was created
	   ;; in the first place.
	   (eq (window-buffer window) (nth 3 quit-restore)))
      (setq resize (with-current-buffer buffer temp-buffer-resize-mode))
      ;; Unrecord buffer.
      (unrecord-buffer buffer)
      (unrecord-window-buffer window buffer)
      ;; Display buffer stored in the quit-restore parameter.
      (set-window-dedicated-p window nil)
      (set-window-buffer window (nth 0 quit-restore))
      (set-window-start window (nth 1 quit-restore))
      (set-window-point window (nth 2 quit-restore))
      (when (and resize (/= (nth 4 quit-restore) (window-total-size window)))
	(resize-window
	 window (- (nth 4 quit-restore) (window-total-size window))))
      ;; Reset the quit-restore parameter.
      (set-window-parameter window 'quit-restore nil)
      (when (window-live-p (nth 5 quit-restore))
	(select-window (nth 5 quit-restore))))
     (t
      ;; Otherwise, show another buffer in WINDOW and reset the
      ;; quit-restore parameter.
      (set-window-parameter window 'quit-restore nil)
      (unrecord-buffer buffer)
      (switch-to-prev-buffer window 'bury-or-kill)))

    ;; Kill WINDOW's old-buffer if requested
    (when kill (kill-buffer buffer))
    nil))

;;; Splitting windows.
(defsubst window-split-min-size (&optional horizontal)
  "Return minimum height of any window when splitting windows.
Optional argument HORIZONTAL non-nil means return minimum width."
  (if horizontal
      (max window-min-width window-safe-min-width)
    (max window-min-height window-safe-min-height)))

(defun split-window (&optional window size side)
  "Make a new window adjacent to WINDOW.
WINDOW can be any window and defaults to the selected one.
Return the new window which is always a live window.

Optional argument SIZE a positive number means make WINDOW SIZE
lines or columns tall.  If SIZE is negative, make the new window
-SIZE lines or columns tall.  If and only if SIZE is non-nil, its
absolute value can be less than `window-min-height' or
`window-min-width'; so this command can make a new window as
small as one line or two columns.  SIZE defaults to half of
WINDOW's size.  Interactively, SIZE is the prefix argument.

Optional third argument SIDE nil (or `below') specifies that the
new window shall be located below WINDOW.  SIDE `above' means the
new window shall be located above WINDOW.  In both cases SIZE
specifies the new number of lines for WINDOW \(or the new window
if SIZE is negative) including space reserved for the mode and/or
header line.

SIDE t (or `right') specifies that the new window shall be
located on the right side of WINDOW.  SIDE `left' means the new
window shall be located on the left of WINDOW.  In both cases
SIZE specifies the new number of columns for WINDOW \(or the new
window provided SIZE is negative) including space reserved for
fringes and the scrollbar or a divider column.  Any other non-nil
value for SIDE is currently handled like t (or `right').

If the variable `ignore-window-parameters' is non-nil or the
`split-window' parameter of WINDOW equals t, do not process any
parameters of WINDOW.  Otherwise, if the `split-window' parameter
of WINDOW specifies a function, call that function with all three
arguments and return the value returned by that function.

Otherwise, if WINDOW is part of an atomic window, \"split\" the
root of that atomic window.  The new window does not become a
member of that atomic window.

If WINDOW is live, properties of the new window like margins and
scrollbars are inherited from WINDOW.  If WINDOW is an internal
window, these properties as well as the buffer displayed in the
new window are inherited from the window selected on WINDOW's
frame.  The selected window is not changed by this function."
  (interactive "i")
  (setq window (normalize-any-window window))
  (let* ((side (cond
		((not side) 'below)
		((memq side '(below above right left)) side)
		(t 'right)))
	 (horizontal (not (memq side '(nil below above))))
	 (frame (window-frame window))
	 (parent (window-parent window))
	 (function (window-parameter window 'split-window))
	 (window-side (window-parameter window 'window-side))
	 ;; Rebind `window-nest' since in some cases we may have to
	 ;; override its value.
	 (window-nest window-nest)
	 atom-root)

    (window-check frame)
    (catch 'done
      (cond
       ;; Ignore window parameters if either `ignore-window-parameters'
       ;; is t or the `split-window' parameter equals t.
       ((or ignore-window-parameters (eq function t)))
       ((functionp function)
	;; The `split-window' parameter specifies the function to call.
	;; If that function is `ignore', do nothing.
	(throw 'done (funcall function window size side)))
       ;; If WINDOW is a subwindow of an atomic window, split the root
       ;; window of that atomic window instead.
       ((and (window-parameter window 'window-atom)
	     (setq atom-root (window-atom-root window))
	     (not (eq atom-root window)))
	(throw 'done (split-window atom-root size side))))

      (when (and window-side
		 (or (not parent)
		     (not (window-parameter parent 'window-side))))
	;; WINDOW is a side root window.  To make sure that a new parent
	;; window gets created set `window-nest' to t.
	(setq window-nest t))

      (when (and window-splits size (> size 0))
	;; If `window-splits' is non-nil and SIZE is a non-negative
	;; integer, we cannot reasonably resize other windows.  Rather
	;; bind `window-nest' to t to make sure that subsequent window
	;; deletions are handled correctly.
	(setq window-nest t))

      (let* ((parent-size
	      ;; `parent-size' is the size of WINDOW's parent, provided
	      ;; it has one.
	      (when parent (window-total-size parent horizontal)))
	     ;; `resize' non-nil means we are supposed to resize other
	     ;; windows in WINDOW's combination.
	     (resize
	      (and window-splits (not window-nest)
		   ;; Resize makes sense in iso-combinations only.
		   (window-iso-combined-p window horizontal)))
	     ;; `old-size' is the current size of WINDOW.
	     (old-size (window-total-size window horizontal))
	     ;; `new-size' is the specified or calculated size of the
	     ;; new window.
	     (new-size
	      (cond
	       ((not size)
		(max (window-split-min-size horizontal)
		     (if resize
			 ;; When resizing try to give the new window the
			 ;; average size of a window in its combination.
			 (min (- parent-size
				 (window-min-size parent horizontal))
			      (/ parent-size
				 (1+ (window-iso-combinations
				      parent horizontal))))
		       ;; Else try to give the new window half the size
		       ;; of WINDOW (plus an eventual odd line).
		       (+ (/ old-size 2) (% old-size 2)))))
	       ((>= size 0)
		;; SIZE non-negative specifies the new size of WINDOW.

		;; Note: Specifying a non-negative SIZE is practically
		;; always done as workaround for making the new window
		;; appear above or on the left of the new window (the
		;; ispell window is a typical example of that).  In all
		;; these cases the SIDE argument should be set to 'above
		;; or 'left in order to support the 'resize option.
		;; Here we have to nest the windows instead, see above.
		(- old-size size))
	       (t
		;; SIZE negative specifies the size of the new window.
		(- size))))
	     new-parent new-normal)

	;; Check SIZE.
	(cond
	 ((not size)
	  (cond
	   (resize
	    ;; SIZE unspecified, resizing.
	    (when (and (not (window-sizable-p parent (- new-size) horizontal))
		       ;; Try again with minimum split size.
		       (setq new-size
			     (max new-size (window-split-min-size horizontal)))
		       (not (window-sizable-p parent (- new-size) horizontal)))
	      (error "Window %s too small for splitting" parent)))
	   ((> (+ new-size (window-min-size window horizontal)) old-size)
	    ;; SIZE unspecified, no resizing.
	    (error "Window %s too small for splitting" window))))
	 ((and (>= size 0)
	       (or (>= size old-size)
		   (< new-size (if horizontal
				   window-safe-min-width
				 window-safe-min-width))))
	  ;; SIZE specified as new size of old window.  If the new size
	  ;; is larger than the old size or the size of the new window
	  ;; would be less than the safe minimum, signal an error.
	  (error "Window %s too small for splitting" window))
	 (resize
	  ;; SIZE specified, resizing.
	  (unless (window-sizable-p parent (- new-size) horizontal)
	    ;; If we cannot resize the parent give up.
	    (error "Window %s too small for splitting" parent)))
	 ((or (< new-size
		 (if horizontal window-safe-min-width window-safe-min-height))
	      (< (- old-size new-size)
		 (if horizontal window-safe-min-width window-safe-min-height)))
	  ;; SIZE specification violates minimum size restrictions.
	  (error "Window %s too small for splitting" window)))

	(resize-window-reset frame horizontal)

	(setq new-parent
	      ;; Make new-parent non-nil if we need a new parent window;
	      ;; either because we want to nest or because WINDOW is not
	      ;; iso-combined.
	      (or window-nest (not (window-iso-combined-p window horizontal))))
	(setq new-normal
	      ;; Make new-normal the normal size of the new window.
	      (cond
	       (size (/ (float new-size) (if new-parent old-size parent-size)))
	       (new-parent 0.5)
	       (resize (/ 1.0 (1+ (window-iso-combinations parent horizontal))))
	       (t (/ (window-normal-size window horizontal) 2.0))))

	(if resize
	    ;; Try to get space from OLD's siblings.  We could go "up" and
	    ;; try getting additional space from surrounding windows but
	    ;; we won't be able to return space to those windows when we
	    ;; delete the one we create here.  Hence we do not go up.
	    (progn
	      (resize-subwindows parent (- new-size) horizontal)
	      (let* ((normal (- 1.0 new-normal))
		     (sub (window-child parent)))
		(while sub
		  (set-window-new-normal
		   sub (* (window-normal-size sub horizontal) normal))
		  (setq sub (window-right sub)))))
	  ;; Get entire space from WINDOW.
	  (set-window-new-total window (- old-size new-size))
	  (resize-this-window window (- new-size) horizontal)
	  (set-window-new-normal
	   window (- (if new-parent 1.0 (window-normal-size window horizontal))
		     new-normal)))

	(let* ((new (split-window-internal window new-size side new-normal)))
	  ;; Inherit window-side parameters, if any.
	  (when (and window-side new-parent)
	    (set-window-parameter (window-parent new) 'window-side window-side)
	    (set-window-parameter new 'window-side window-side))

	  (run-window-configuration-change-hook frame)
	  (window-check frame)
	  ;; Always return the new window.
	  new)))))

;; I think this should be the default; I think people will prefer it--rms.
(defcustom split-window-keep-point t
  "If non-nil, \\[split-window-above-each-other] keeps the original point \
in both children.
This is often more convenient for editing.
If nil, adjust point in each of the two windows to minimize redisplay.
This is convenient on slow terminals, but point can move strangely.

This option applies only to `split-window-above-each-other' and
functions that call it.  `split-window' always keeps the original
point in both children."
  :type 'boolean
  :group 'windows)

(defun split-window-above-each-other (&optional size)
  "Split selected window into two windows, one above the other.
The upper window gets SIZE lines and the lower one gets the rest.
SIZE negative means the lower window gets -SIZE lines and the
upper one the rest.  With no argument, split windows equally or
close to it.  Both windows display the same buffer, now current.

If the variable `split-window-keep-point' is non-nil, both new
windows will get the same value of point as the selected window.
This is often more convenient for editing.  The upper window is
the selected window.

Otherwise, we choose window starts so as to minimize the amount of
redisplay; this is convenient on slow terminals.  The new selected
window is the one that the current value of point appears in.  The
value of point can change if the text around point is hidden by the
new mode line.

Regardless of the value of `split-window-keep-point', the upper
window is the original one and the return value is the new, lower
window."
  (interactive "P")
  (let ((old-window (selected-window))
	(old-point (point))
	(size (and size (prefix-numeric-value size)))
        moved-by-window-height moved new-window bottom)
    (when (and size (< size 0) (< (- size) window-min-height))
      ;; `split-window' would not signal an error here.
      (error "Size of new window too small"))
    (setq new-window (split-window nil size))
    (unless split-window-keep-point
      (with-current-buffer (window-buffer)
	(goto-char (window-start))
	(setq moved (vertical-motion (window-height)))
	(set-window-start new-window (point))
	(when (> (point) (window-point new-window))
	  (set-window-point new-window (point)))
	(when (= moved (window-height))
	  (setq moved-by-window-height t)
	  (vertical-motion -1))
	(setq bottom (point)))
      (and moved-by-window-height
	   (<= bottom (point))
	   (set-window-point old-window (1- bottom)))
      (and moved-by-window-height
	   (<= (window-start new-window) old-point)
	   (set-window-point new-window old-point)
	   (select-window new-window)))
    ;; Always copy quit-restore parameter in interactive use.
    (let ((quit-restore (window-parameter old-window 'quit-restore)))
      (when quit-restore
	(set-window-parameter new-window 'quit-restore quit-restore)))
    new-window))

(defalias 'split-window-vertically 'split-window-above-each-other)

(defun split-window-side-by-side (&optional size)
  "Split selected window into two windows side by side.
The selected window becomes the left one and gets SIZE columns.
SIZE negative means the right window gets -SIZE lines.

SIZE includes the width of the window's scroll bar; if there are
no scroll bars, it includes the width of the divider column to
the window's right, if any.  SIZE omitted or nil means split
window equally.

The selected window remains selected.  Return the new window."
  (interactive "P")
  (let ((old-window (selected-window))
	(size (and size (prefix-numeric-value size)))
	new-window)
    (when (and size (< size 0) (< (- size) window-min-width))
      ;; `split-window' would not signal an error here.
      (error "Size of new window too small"))
    (setq new-window (split-window nil size t))
    ;; Always copy quit-restore parameter in interactive use.
    (let ((quit-restore (window-parameter old-window 'quit-restore)))
      (when quit-restore
	(set-window-parameter new-window 'quit-restore quit-restore)))
    new-window))

(defalias 'split-window-horizontally 'split-window-side-by-side)

;;; Balancing windows.

;; The following routine uses the recycled code from an old version of
;; `resize-subwindows'.  It's not very pretty, but coding it the way the
;; new `resize-subwindows' code does would hardly make it any shorter or
;; more readable (FWIW we'd need three loops - one to calculate the
;; minimum sizes per window, one to enlarge or shrink windows until the
;; new parent-size matches, and one where we shrink the largest/enlarge
;; the smallest window).
(defun balance-windows-2 (window horizontal)
  "Subroutine of `balance-windows-1'.
WINDOW must be an iso-combination."
  (let* ((first (window-child window))
	 (sub first)
	 (number-of-children 0)
	 (parent-size (window-new-total window))
	 (total-sum parent-size)
	 found failed size sub-total sub-delta sub-amount rest)
    (while sub
      (setq number-of-children (1+ number-of-children))
      (when (window-size-fixed-p sub horizontal)
	(setq total-sum
	      (- total-sum (window-total-size sub horizontal)))
	(set-window-new-normal sub 'ignore))
      (setq sub (window-right sub)))

    (setq failed t)
    (while (and failed (> number-of-children 0))
      (setq size (/ total-sum number-of-children))
      (setq failed nil)
      (setq sub first)
      (while (and sub (not failed))
	;; Ignore subwindows that should be ignored or are stuck.
	(unless (resize-subwindows-skip-p sub)
	  (setq found t)
	  (setq sub-total (window-total-size sub horizontal))
	  (setq sub-delta (- size sub-total))
	  (setq sub-amount
		(window-sizable sub sub-delta horizontal))
	  ;; Register the new total size for this subwindow.
	  (set-window-new-total sub (+ sub-total sub-amount))
	  (unless (= sub-amount sub-delta)
	    (setq total-sum (- total-sum sub-total sub-amount))
	    (setq number-of-children (1- number-of-children))
	    ;; We failed and need a new round.
	    (setq failed t)
	    (set-window-new-normal sub 'skip)))
	(setq sub (window-right sub))))

    (setq rest (% total-sum number-of-children))
    ;; Fix rounding by trying to enlarge non-stuck windows by one line
    ;; (column) until `rest' is zero.
    (setq sub first)
    (while (and sub (> rest 0))
      (unless (resize-subwindows-skip-p window)
	(set-window-new-total sub 1 t)
	(setq rest (1- rest)))
      (setq sub (window-right sub)))

    ;; Fix rounding by trying to enlarge stuck windows by one line
    ;; (column) until `rest' equals zero.
    (setq sub first)
    (while (and sub (> rest 0))
      (unless (eq (window-new-normal sub) 'ignore)
	(set-window-new-total sub 1 t)
	(setq rest (1- rest)))
      (setq sub (window-right sub)))

    (setq sub first)
    (while sub
      ;; Record new normal sizes.
      (set-window-new-normal
       sub (/ (if (eq (window-new-normal sub) 'ignore)
		  (window-total-size sub horizontal)
		(window-new-total sub))
	      (float parent-size)))
      ;; Recursively balance each subwindow's subwindows.
      (balance-windows-1 sub horizontal)
      (setq sub (window-right sub)))))

(defun balance-windows-1 (window &optional horizontal)
  "Subroutine of `balance-windows'."
  (if (window-child window)
      (let ((sub (window-child window)))
	(if (window-iso-combined-p sub horizontal)
	    (balance-windows-2 window horizontal)
	  (let ((size (window-new-total window)))
	    (while sub
	      (set-window-new-total sub size) 
	      (balance-windows-1 sub horizontal)
	      (setq sub (window-right sub))))))))

(defun balance-windows (&optional window-or-frame)
  "Balance the sizes of subwindows of WINDOW-OR-FRAME.
WINDOW-OR-FRAME is optional and defaults to the selected frame.
If WINDOW-OR-FRAME denotes a frame, balance the sizes of all
subwindows of that frame's root window.  If WINDOW-OR-FRAME
denots a window, balance the sizes of all subwindows of that
window."
  (interactive)
  (let* ((window
	  (cond
	   ((or (not window-or-frame)
		(frame-live-p window-or-frame))
	    (frame-root-window window-or-frame))
	   ((or (window-live-p window-or-frame)
		(window-child window-or-frame))
	    window-or-frame)
	   (t
	    (error "Not a window or frame %s" window-or-frame))))
	 (frame (window-frame window)))
    ;; Balance vertically.
    (resize-window-reset (window-frame window))
    (balance-windows-1 window)
    (resize-window-apply frame)
    ;; Balance horizontally.
    (resize-window-reset (window-frame window) t)
    (balance-windows-1 window t)
    (resize-window-apply frame t)))

(defun window-fixed-size-p (&optional window direction)
  "Return t if WINDOW cannot be resized in DIRECTION.
WINDOW defaults to the selected window.  DIRECTION can be
nil (i.e. any), `height' or `width'."
  (with-current-buffer (window-buffer window)
    (when (and (boundp 'window-size-fixed) window-size-fixed)
      (not (and direction
		(member (cons direction window-size-fixed)
			'((height . width) (width . height))))))))

;;; A different solution to balance-windows.
(defvar window-area-factor 1
  "Factor by which the window area should be over-estimated.
This is used by `balance-windows-area'.
Changing this globally has no effect.")
(make-variable-buffer-local 'window-area-factor)

(defun balance-windows-area-adjust (window delta horizontal)
  "Wrapper around `resize-window' with error checking.
Arguments WINDOW, DELTA and HORIZONTAL are passed on to that function."
  ;; `resize-window' may fail if delta is too large.
  (while (>= (abs delta) 1)
    (condition-case nil
        (progn
          (resize-window window delta horizontal)
          (setq delta 0))
      (error
       ;;(message "adjust: %s" (error-message-string err))
       (setq delta (/ delta 2))))))

(defun balance-windows-area ()
  "Make all visible windows the same area (approximately).
See also `window-area-factor' to change the relative size of
specific buffers."
  (interactive)
  (let* ((unchanged 0) (carry 0) (round 0)
         ;; Remove fixed-size windows.
         (wins (delq nil (mapcar (lambda (win)
                                   (if (not (window-fixed-size-p win)) win))
                                 (window-list nil 'nomini))))
         (changelog nil)
         next)
    ;; Resizing a window changes the size of surrounding windows in complex
    ;; ways, so it's difficult to balance them all.  The introduction of
    ;; `adjust-window-trailing-edge' made it a bit easier, but it is still
    ;; very difficult to do.  `balance-window' above takes an off-line
    ;; approach: get the whole window tree, then balance it, then try to
    ;; adjust the windows so they fit the result.
    ;; Here, instead, we take a "local optimization" approach, where we just
    ;; go through all the windows several times until nothing needs to be
    ;; changed.  The main problem with this approach is that it's difficult
    ;; to make sure it terminates, so we use some heuristic to try and break
    ;; off infinite loops.
    ;; After a round without any change, we allow a second, to give a chance
    ;; to the carry to propagate a minor imbalance from the end back to
    ;; the beginning.
    (while (< unchanged 2)
      ;; (message "New round")
      (setq unchanged (1+ unchanged) round (1+ round))
      (dolist (win wins)
        (setq next win)
        (while (progn (setq next (next-window next))
                      (window-fixed-size-p next)))
        ;; (assert (eq next (or (cadr (member win wins)) (car wins))))
        (let* ((horiz
                (< (car (window-edges win)) (car (window-edges next))))
               (areadiff (/ (- (* (window-height next) (window-width next)
                                  (buffer-local-value 'window-area-factor
                                                      (window-buffer next)))
                               (* (window-height win) (window-width win)
                                  (buffer-local-value 'window-area-factor
                                                      (window-buffer win))))
                            (max (buffer-local-value 'window-area-factor
                                                     (window-buffer win))
                                 (buffer-local-value 'window-area-factor
                                                     (window-buffer next)))))
               (edgesize (if horiz
                             (+ (window-height win) (window-height next))
                           (+ (window-width win) (window-width next))))
               (diff (/ areadiff edgesize)))
          (when (zerop diff)
            ;; Maybe diff is actually closer to 1 than to 0.
            (setq diff (/ (* 3 areadiff) (* 2 edgesize))))
          (when (and (zerop diff) (not (zerop areadiff)))
            (setq diff (/ (+ areadiff carry) edgesize))
            ;; Change things smoothly.
            (if (or (> diff 1) (< diff -1)) (setq diff (/ diff 2))))
          (if (zerop diff)
              ;; Make sure negligible differences don't accumulate to
              ;; become significant.
              (setq carry (+ carry areadiff))
	    ;; This used `adjust-window-trailing-edge' before and uses
	    ;; `resize-window' now.  Error wrapping is still needed.
	    (balance-windows-area-adjust win diff horiz)
            ;; (sit-for 0.5)
            (let ((change (cons win (window-edges win))))
              ;; If the same change has been seen already for this window,
              ;; we're most likely in an endless loop, so don't count it as
              ;; a change.
              (unless (member change changelog)
                (push change changelog)
                (setq unchanged 0 carry 0)))))))
    ;; We've now basically balanced all the windows.
    ;; But there may be some minor off-by-one imbalance left over,
    ;; so let's do some fine tuning.
    ;; (bw-finetune wins)
    ;; (message "Done in %d rounds" round)
    ))

;;; Window states, how to get them and how to put them in a window.
(defsubst window-list-no-nils (&rest args)
  "Like LIST but do not add nil elements of ARGS."
  (delq nil (apply 'list args)))

(defvar window-state-ignored-parameters '(quit-restore)
  "List of window parameters ignored by `window-state-get'.")

(defun window-state-get-1 (window &optional markers)
  "Helper function for `window-state-get'."
  (let* ((type
	  (cond
	   ((window-vchild window) 'vc)
	   ((window-hchild window) 'hc)
	   (t 'leaf)))
	 (buffer (window-buffer window))
	 (selected (eq window (selected-window)))
	 (head
	  (window-list-no-nils
	   type
	   (unless (window-next window) (cons 'last t))
	   (cons 'clone-number (window-clone-number window))
	   (cons 'total-height (window-total-size window))
	   (cons 'total-width (window-total-size window t))
	   (cons 'normal-height (window-normal-size window))
	   (cons 'normal-width (window-normal-size window t))
	   (cons 'splits (window-splits window))
	   (cons 'nest (window-nest window))
	   (let (list)
	     (dolist (parameter (window-parameters window))
	       (unless (memq (car parameter)
			     window-state-ignored-parameters)
		 (setq list (cons parameter list))))
	     (when list
	       (cons 'parameters list)))
	   (when buffer
	     ;; All buffer related things go in here - make the buffer
	     ;; current when retrieving `point' and `mark'.
	     (with-current-buffer (window-buffer window)
	       (let ((point (if selected (point) (window-point window)))
		     (start (window-start window))
		     (mark (mark)))
		 (window-list-no-nils
		  'buffer (buffer-name buffer)
		  (cons 'selected selected)
		  (when window-size-fixed (cons 'size-fixed window-size-fixed))
		  (cons 'hscroll (window-hscroll window))
		  (cons 'fringes (window-fringes window))
		  (cons 'margins (window-margins window))
		  (cons 'scroll-bars (window-scroll-bars window))
		  (cons 'vscroll (window-vscroll window))
		  (cons 'dedicated (window-dedicated-p window))
		  (cons 'point (if markers (copy-marker point) point))
		  (cons 'start (if markers (copy-marker start) start))
		  (when mark
		    (cons 'mark (if markers (copy-marker mark) mark)))))))))
	 (tail
	  (when (memq type '(vc hc))
	    (let (list)
	      (setq window (window-child window))
	      (while window
		(setq list (cons (window-state-get-1 window markers) list))
		(setq window (window-right window)))
	      (nreverse list)))))
    (append head tail)))

(defun window-state-get (&optional window markers)
  "Return state of WINDOW as a Lisp object.
WINDOW can be any window and defaults to the root window of the
selected frame.

Optional argument MARKERS non-nil means use markers for sampling
positions like `window-point' or `window-start'.  MARKERS should
be non-nil only if the value is used for putting the state back
in the same session (note that markers slow down processing).

The return value can be used as argument for `window-state-put'
to put the state recorded here into an arbitrary window.  The
value can be also stored on disk and read back in a new session."
  (setq window
	(if window
	    (if (window-any-p window)
		window
	      (error "%s is not a live or internal window" window))
	  (frame-root-window)))
  ;; The return value is a cons whose car specifies some constraints on
  ;; the size of WINDOW.  The cdr lists the states of the subwindows of
  ;; WINDOW.
  (cons
   ;; Frame related things would go into a function, say `frame-state',
   ;; calling `window-state-get' to insert the frame's root window.
   (window-list-no-nils
    (cons 'min-height (window-min-size window))
    (cons 'min-width (window-min-size window t))
    (cons 'min-height-ignore (window-min-size window nil t))
    (cons 'min-width-ignore (window-min-size window t t))
    (cons 'min-height-safe (window-min-size window nil 'safe))
    (cons 'min-width-safe (window-min-size window t 'safe))
    ;; These are probably not needed.
    (when (window-size-fixed-p window) (cons 'fixed-height t))
    (when (window-size-fixed-p window t) (cons 'fixed-width t)))
   (window-state-get-1 window markers)))

(defvar window-state-put-list nil
  "Helper variable for `window-state-put'.")

(defun window-state-put-1 (state &optional window ignore totals)
  "Helper function for `window-state-put'."
  (let ((type (car state)))
    (setq state (cdr state))
    (cond
     ((eq type 'leaf)
      ;; For a leaf window just add unprocessed entries to
      ;; `window-state-put-list'.
      (setq window-state-put-list
	    (cons (cons window state) window-state-put-list)))
     ((memq type '(vc hc))
      (let* ((horizontal (eq type 'hc))
	     (total (window-total-size window horizontal))
	     (first t)
	     size new)
	(dolist (item state)
	  ;; Find the next child window.  WINDOW always points to the
	  ;; real window that we want to fill with what we find here.
	  (when (memq (car item) '(leaf vc hc))
	    (if (assq 'last item)
		;; The last child window.  Below `window-state-put-1'
		;; will put into it whatever ITEM has in store.
		(setq new nil)
	      ;; Not the last child window, prepare for splitting
	      ;; WINDOW.  SIZE is the new (and final) size of the old
	      ;; window.
	      (setq size
		    (if totals
			;; Use total size.
			(cdr (assq (if horizontal 'total-width 'total-height) item))
		      ;; Use normalized size and round.
		      (round (* total
				(cdr (assq
				      (if horizontal 'normal-width 'normal-height)
				      item))))))

	      ;; Use safe sizes, we try to resize later.
	      (setq size (max size (if horizontal
				       window-safe-min-height
				     window-safe-min-width)))

	      (if (window-sizable-p window (- size) horizontal 'safe)
		  (let* ((window-nest (assq 'nest item)))
		    ;; We must inherit the nesting, otherwise we might mess
		    ;; up handling of atomic and side window.
		    (setq new (split-window window size horizontal)))
		;; Give up if we can't resize window down to safe sizes.
		(error "Cannot resize window %s" window))

	      (when first
		(setq first nil)
		;; When creating the first child window add for parent
		;; unprocessed entries to `window-state-put-list'.
		(setq window-state-put-list
		      (cons (cons (window-parent window) state)
			    window-state-put-list))))

	    ;; Now process the current window (either the one we've just
	    ;; split or the last child of its parent).
	    (window-state-put-1 item window ignore totals)
	    ;; Continue with the last window split off.
	    (setq window new))))))))

(defun window-state-put-2 (ignore)
  "Helper function for `window-state-put'."
  (dolist (item window-state-put-list)
    (let ((window (car item))
	  (clone-number (cdr (assq 'clone-number item)))
	  (splits (cdr (assq 'splits item)))
	  (nest (cdr (assq 'nest item)))
	  (parameters (cdr (assq 'parameters item)))
	  (state (cdr (assq 'buffer item))))
      ;; Put in clone-number.
      (when clone-number (set-window-clone-number window clone-number))
      (when splits (set-window-splits window splits))
      (when nest (set-window-nest window nest))
      ;; Process parameters.
      (when parameters
	(dolist (parameter parameters)
	  (set-window-parameter window (car parameter) (cdr parameter))))
      ;; Process buffer related state.
      (when state
	;; We don't want to raise an error here so we create a buffer if
	;; there's none.
	(set-window-buffer window (get-buffer-create (car state)))
	(with-current-buffer (window-buffer window)
	  (set-window-hscroll window (cdr (assq 'hscroll state)))
	  (apply 'set-window-fringes
		 (cons window (cdr (assq 'fringes state))))
	  (let ((margins (cdr (assq 'margins state))))
	    (set-window-margins window (car margins) (cdr margins)))
	  (let ((scroll-bars (cdr (assq 'scroll-bars state))))
	    (set-window-scroll-bars
	     window (car scroll-bars) (nth 2 scroll-bars) (nth 3 scroll-bars)))
	  (set-window-vscroll window (cdr (assq 'vscroll state)))
	  ;; Adjust vertically.
	  (if (memq window-size-fixed '(t height))
	      ;; A fixed height window, try to restore the original size.
	      (let ((delta (- (cdr (assq 'total-height item))
			      (window-total-height window)))
		    window-size-fixed)
		(when (window-resizable-p window delta)
		  (resize-window window delta)))
	    ;; Else check whether the window is not high enough.
	    (let* ((min-size (window-min-size window nil ignore))
		   (delta (- min-size (window-total-size window))))
	      (when (and (> delta 0)
			 (window-resizable-p window delta nil ignore))
		(resize-window window delta nil ignore))))
	  ;; Adjust horizontally.
	  (if (memq window-size-fixed '(t width))
	      ;; A fixed width window, try to restore the original size.
	      (let ((delta (- (cdr (assq 'total-width item))
			      (window-total-width window)))
		    window-size-fixed)
		(when (window-resizable-p window delta)
		  (resize-window window delta)))
	    ;; Else check whether the window is not wide enough.
	    (let* ((min-size (window-min-size window t ignore))
		   (delta (- min-size (window-total-size window t))))
	      (when (and (> delta 0)
			 (window-resizable-p window delta t ignore))
		(resize-window window delta t ignore))))
	  ;; Set dedicated status.
	  (set-window-dedicated-p window (cdr (assq 'dedicated state)))
	  ;; Install positions (maybe we should do this after all windows
	  ;; have been created and sized).
	  (ignore-errors
	    (set-window-start window (cdr (assq 'start state)))
	    (set-window-point window (cdr (assq 'point state)))
	    ;; I'm not sure whether we should set the mark here, but maybe
	    ;; it can be used.
	    (let ((mark (cdr (assq 'mark state))))
	      (when mark (set-mark mark))))
	  ;; Select window if it's the selected one.
	  (when (cdr (assq 'selected state))
	    (select-window window)))))))

(defun window-state-put (state &optional window ignore)
  "Put window state STATE into WINDOW.
STATE should be the state of a window returned by an earlier
invocation of `window-state-get'.  Optional argument WINDOW must
specify a live window and defaults to the selected one.

Optional argument IGNORE non-nil means ignore minimum window
sizes and fixed size restrictions.  IGNORE equal `safe' means
subwindows can get as small as `window-safe-min-height' and
`window-safe-min-width'."
  (setq window (normalize-live-window window))
  (let* ((frame (window-frame window))
	 (head (car state))
	 ;; We check here (1) whether the total sizes of root window of
	 ;; STATE and that of WINDOW are equal so we can avoid
	 ;; calculating new sizes, and (2) if we do have to resize
	 ;; whether we can do so without violating size restrictions.
	 (totals
	  (and (= (window-total-size window)
		  (cdr (assq 'total-height state)))
	       (= (window-total-size window t)
		  (cdr (assq 'total-width state)))))
	 (min-height (cdr (assq 'min-height head)))
	 (min-width (cdr (assq 'min-width head)))
	 window-splits selected)
    (if (and (not totals)
	     (or (> min-height (window-total-size window))
		 (> min-width (window-total-size window t)))
	     (or (not ignore)
		 (and (setq min-height
			    (cdr (assq 'min-height-ignore head)))
		      (setq min-width
			    (cdr (assq 'min-width-ignore head)))
		      (or (> min-height (window-total-size window))
			  (> min-width (window-total-size window t)))
		      (or (not (eq ignore 'safe))
			  (and (setq min-height
				     (cdr (assq 'min-height-safe head)))
			       (setq min-width
				     (cdr (assq 'min-width-safe head)))
			       (or (> min-height
				      (window-total-size window))
				   (> min-width
				      (window-total-size window t))))))))
	;; The check above might not catch all errors due to rounding
	;; issues - so IGNORE equal 'safe might not always produce the
	;; minimum possible state.  But such configurations hardly make
	;; sense anyway.
	(error "Window %s too small to accomodate state" window)
      (setq state (cdr state))
      (setq window-state-put-list nil)
      ;; Work on the windows of a temporary buffer to make sure that
      ;; splitting proceeds regardless of any buffer local values of
      ;; `window-size-fixed'.  Release that buffer after the buffers of
      ;; all live windows have been set by `window-state-put-2'.
      (with-temp-buffer
	(set-window-buffer window (current-buffer))
	(window-state-put-1 state window nil totals)
	(window-state-put-2 ignore))
      (window-check frame))))

;;; Displaying buffers.
(defconst display-buffer-default-specifiers
  '((reuse-window nil same visible)
    (pop-up-window (largest . nil) (lru . nil))
    (pop-up-window-min-height . 40)
    (pop-up-window-min-width . 80)
    (reuse-window other nil nil)
    (reuse-window nil other visible)
    (reuse-window nil nil t)
    (reuse-window-even-sizes . t))
  "Buffer display default specifiers.
The value specified here is used when no other specifiers have
been specified by the user or the application.  Consult the
documentation of `display-buffer-alist' for a description of
buffer display specifiers.")

(defconst display-buffer-macro-specifiers
  '((same-window
     ;; Use the same window.
     (reuse-window same nil nil))
    (same-frame
     ;; Avoid other frames.
     (reuse-window nil same nil)
     (pop-up-window (largest . nil) (lru . nil))
     (reuse-window nil other nil))
    ;; (other-window
    ;;  ;; Avoid selected window.
    ;;  (reuse-window other same visible)
    ;;  (pop-up-window (largest . nil) (lru . nil))
    ;;  (reuse-window other other visible))
    (same-frame-other-window
     ;; Avoid other frames and selected window.
     (reuse-window other same nil)
     (pop-up-window (largest . nil) (lru . nil))
     (reuse-window other other nil))
    (other-frame
     ;; Avoid selected frame.
     (reuse-window nil same other)
     (pop-up-frame)
     (reuse-window nil other other))
    (default
      ;; The default specifiers.
      display-buffer-default-specifiers))
  "Buffer display macro specifiers.")

(defcustom display-buffer-alist
  '((((regexp . ".*"))
     ;; Reuse window showing same buffer on same frame.
     reuse-window (reuse-window nil same nil)
     ;; Pop up window.
     pop-up-window
     ;; Split largest or lru window.
     (pop-up-window (largest . nil) (lru . nil))
     (pop-up-window-min-height . 40) ; split-height-threshold / 2
     (pop-up-window-min-width . 80) ; split-width-threshold / 2
     ;; Reuse any but selected window on same frame.
     reuse-window (reuse-window other nil nil)
     (reuse-window-even-sizes . t)))
  "List associating buffer identifiers with display specifiers.
The car of each element of this list is built from a set of cons
cells called buffer identifiers.  `display-buffer' shows a buffer
according to the display specifiers in the element's cdr
\(elements are true lists) if at least one of the identifiers
matches the first or third argument of `display-buffer'.  Such a
match occurs in one of the following three cases:

- The car of the buffer identifier is the symbol `name' and its
  cdr is a string equalling the name of the buffer specified by
  the first \(BUFFER-OR-NAME) argument of `display-buffer'.

- The car is the symbol `regexp' and the cdr is a regular
  expression matching the name of the buffer specified by the
  first \(BUFFER-OR-NAME) argument of `display-buffer'.

- The car is the symbol `label' and the cdr is a symbol equalling
  the third \(LABEL) argument of `display-buffer'.

Display specifiers are either symbols, cons cells, or lists.
Five specifiers have been reserved to indicate the basic method
for displaying the buffer: `reuse-window', `pop-up-window',
`pop-up-frame', `use-side-window', and `fun-with-args'.

A list whose car is the symbol `reuse-window' indicates that an
existing window shall be reused for displaying the buffer.  The
second element of this list specifies the window to use and can
be one of the following symbols:

  nil stands for any window.

  `same' stands for the selected window.

  `other' stands for any but the selected window.

The third element specifies whether the buffer shown in a window
that shall be reused must be the same buffer that shall be
displayed or another buffer and can be one of the following:

  nil means to not care about the window's buffer.

  `same' means the window must show the buffer already.

  `other' means the window must not show the buffer yet.

The fourth element specifies the set of frames to search for a
suitable window and can be one of the following:

  nil to reuse a window on the selected frame.

  `visible' to search visible frames on the current terminal.

  `other' stands for any visible frame but the selected one.

  0 \(the number zero) to search visible and iconified frames on
  the current terminal.

  t to search arbitrary frames including invisible ones.

If more than one window fits the constraints imposed by these
elements, the least recently used candidate is chosen.  A side
window is never reused unless it already shows the buffer.

The following two specifiers are useful when the method equals
`reuse-window':

- A cons cell whose car is the symbol `reuse-window-even-sizes'
  and whose cdr is non-nil means to even out the sizes of a
  reused window and the selected window provided they (1) appear
  adjacent to each other and (2) the selected window is larger
  than the window chosen.  If the cdr is nil, this means that the
  window sizes are left alone.

- A cons cell whose car is the symbol `reuse-window-dedicated'
  and whose cdr is non-nil means that a window can be reused even
  if it's weakly dedicated to its buffer.  If the cdr is t, a
  strongly dedicated window can be reused to show the buffer.
  Any other non-nil value means only weakly dedicated windows can
  be reused.  If the cdr is nil, dedicated windows are not
  reused.

  This specifier should be used in emergency cases only since
  windows are usually made dedicated in order to prevent
  `display-buffer' from reusing them.

A list whose car is the symbol `pop-up-window' and whose cdr is
built from cons cells representing window/side tuples indicates
that a new window shall be made for displaying the buffer on the
selected frame.

Window/side tuples are cons cells.  The car of such a tuple
identifies the window that shall be split.  Possible values are
`largest', `lru', `selected', and `root' to split the largest,
least recently used, selected or root window of the selected
frame.

If the frame has side windows, these values do allow to split
only the selected frame's main window or one of its subwindows.
Setting the car to one of `left', `top', `right' and `bottom'
splits the corresponding side window, provided such a window
exists.

The cdr of each pair specifies on which side of the window to
split the new window shall appear and can be one of `below',
`right', `above', or `left' with the obvious meanings.  If the
cdr is nil, the window is split in a fashion suitable for its
current dimensions.  If the cdr specifies a function, that
function is called with one argument - the window to split.  The
function is supposed to split that window and return the new
window.

`display-buffer' scans these tuples until it can either produce a
suitable window or fails.  The default value for
`display-buffer-alist' contains the tuples \(largest . nil) and
\(lru . nil) in order to split the largest window first and, if
that fails, the least recently used one.

The following specifiers are useful if the method specifier is
`pop-up-window'.

- A cons cell whose car is the symbol `pop-up-window-min-height'
  specifiies the minimum height of the new window.  If the cdr is
  an integer number, it specifies the minimum number of lines of
  the window.  A floating point number gives the minimum fraction
  of the window height with respect to the height of the frame's
  root window.  A new window is created only if it can be made at
  least as high as specified by the number.  If the cdr is nil,
  this means to use the value of `window-min-height'.

- A cons cell whose car is the symbol `pop-up-window-min-width'
  specifies the minimum width of the new window.  If the cdr is
  an integer number, it specifies the minimum number of columns
  of the window.  A floating point number gives the minimum
  fraction of the window width with respect to the width of the
  frame's root window.  A new window is created only if it can be
  made at least as wide as specified by the number.  If the cdr
  is nil, this means to use the value of `window-min-width'.

- A cons cell whose car is `pop-up-window-set-height' with
  the following interpretations for the cdr:

  - nil means leave the height of the new window alone.

  - A number specifies the desired height of the new window.  An
    integer number specifies the number of lines of the window.
    A floating point number gives the fraction of the window
    height with respect to the height of the frame's root window.

  - If the cdr specifies a function, that function is called with
    one argument - the new window.  The function is supposed to
    adjust the height of the window; its return value is ignored.
    Suitable functions are `shrink-window-if-larger-than-buffer'
    and `fit-window-to-buffer'.

- A cons cell whose car equals `pop-up-window-set-width' with
  the following interpretations for the cdr:

  - nil means leave the width of the new window alone.

  - A number specifies the desired width of the new window.  An
    integer number specifies the number of columns of the window.
    A floating point number gives the fraction of the window
    width with respect to the width of the frame's root window.

  - If the cdr specifies a function, that function is called with
    one argument - the new window.  The function is supposed to
    adjust the width of the window; its return value is ignored.

  Observe that specifying `pop-up-window-set-height' or
  `pop-up-window-set-width' may override restrictions given by
  the `pop-up-window-min-height' and `pop-up-window-min-width'
  specifiers.

- A cons cell whose car is `pop-up-window-split-unsplittable' and
  whose cdr is non-nil allows to make a new window on an
  unsplittable frame.  If the cdr is nil, unsplittable frames are
  not split.  This specifier should be used in special cases only
  since frames are usually made unsplittable in order to prevent
  `display-buffer' from splitting them.

A list whose car is the symbol `pop-up-frame' specifies that a
new frame shall be made for displaying the buffer.  The second
element, if non-nil, allows popping up a new frame on graphic
displays only.

The following specifiers are useful if the method specifier is
`pop-up-frame'.

- A list whose car is the symbol `pop-up-frame-function' together
  with a valid function as cdr specifies the function for
  creating a new frame.  If the cdr is nil, the default function
  `make-frame' is called.  The function is called with the
  parameters and values provided by the specifier described next.

- A list whose car is the symbol `pop-up-frame-alist' followed by
  an arbitrary number of frame parameter/value tuples, each given
  as a cons cell, specifies the parameters passed to the pop-up
  frame function.

A list of three elements whose car is the symbol
`use-side-window' specifies that the buffer shall be displayed in
a side window of the selected frame.  The second element denotes
the side of the frame where the window appears or shall be made.
The third element denotes the slot used by the window.  If a side
window with the specified slot exists already, that window is
reused.  If no such window exists it is created.

The following specifiers are useful in connection with the
`use-side-window' method specifier: `reuse-window-dedicated',
`pop-up-window-min-height', `pop-up-window-min-width',
`pop-up-window-set-height' and `pop-up-window-set-width'.

A list whose car is the symbol `fun-with-args' specifies that the
function specified in the second element of the list is
responsible for displaying the buffer.  `display-buffer' calls
this function with the buffer as first argument and the remaining
elements of the list as second argument.

The function should choose or create a window, display the buffer
in it, and return the window.  It is also responsible for giving
the variable `display-buffer-window' and the `quit-restore'
parameter of the window used a meaningful value.

Within the body of this function avoid calling `display-buffer'
with the same buffer as argument since this may lead to endless
recursion.

Instead of supplying basic method specifiers, it's sometimes more
convenient to use macro specifiers.  They provide some commonly
used display methods but do not support the fine control provided
by the basic method specifiers.  Macro specifiers are symbols.
The following macro specifiers are provided:

  `same-window' to display the buffer in the selected window.

  `same-frame' to display the buffer on the selected frame.

  `other-window' to display the buffer in any window but the
   selected one.

  `same-frame-other-window' as `other-window' but stay on the
  selected frame.

  `other-frame' to display the buffer on another visible
  frame.

  `default' to use the default value of `display-buffer-alist'.

One specifier is useful with any method specifier: A list whose
car is the symbol `dedicate' and whose cdr is non-nil will
dedicate the window to its buffer.  The following values are
supported:

- nil to not dedicate the window to the buffer.

- `weak' to weakly dedicate the window to the buffer.

- t to strongly dedicate the window to the buffer.

A cons cell whose car is `other-window-means-other-frame' and
whose cdr is non-nil means that you want calls of
`display-buffer' with the second argument t or the symbol
`other-window' to display the buffer in another frame.  This
means, for example, that you prefer functions like
`find-file-other-window' or `switch-to-buffer-other-window' to
make a new frame instead of a new window on the selected frame.

Usually, applications are free to override the specifiers of
`display-buffer-alist' by passing their own specifiers as second
argument of `display-buffer'.  For every `display-buffer-alist'
entry you can, however, add a cons cell whose car is the symbol
`override' and whose cdr is non-nil, to explicitly override any
value supplied by the application.

Overriding specifiers supplied by the calling application is, in
general, not advisable.  It permits, for example, to change the
semantics of a function like `display-buffer-other-window' by
using the location specifiers `same-window' or `other-frame'."
  :risky t
  :type
  '(repeat
    :offset 9
    ;; Associations of buffer identifiers and display specifiers.
    (list
     :format "%v"
     ;; Buffer identifiers.
     (repeat
      :tag "Buffer identifiers"
      (choice
       :tag "Identifier"
       :format "%[%t%] %v" :size 15
       (cons
	:tag "Name"
	:format "%v"
	:help-echo "A buffer name."
	(const :format "" name)
	(string :format "Name: %v\n" :size 32))
       (cons
	:tag "Regexp"
	:format "%v"
	:help-echo "A regular expression matching buffer names."
	(const :format "" regexp)
	(string :format "Regexp: %v\n" :size 32))
       (cons
	:tag "Label"
	:format "%v"
	:help-echo "A symbol equalling the buffer display label."
	(const :format "" symbol)
	(symbol :format "Label: %v\n" :size 32))))

     ;; Display specifiers.
     (repeat
      :offset 9
      :tag "Display specifiers"
      :inline t
      (list
       :inline t
       :format "%v"
       (choice
	:tag "Method"
	:value (reuse-window
		(reuse-window nil same nil)
		(reuse-window-even-sizes . t))
	:inline t
	:help-echo "Method for displaying the buffer."
	:format "%[Method%] %v" :size 15

	;; Reuse window specifiers.
	(list
	 :tag "Reuse window"
	 :value (reuse-window
		 (reuse-window nil same nil)
		 (reuse-window-even-sizes . t))
	 :format "%t\n%v"
	 :inline t
	 ;; For customization purposes only.
	 (const :format "" reuse-window)
	 (set
	  :format "%v"
	  :inline t
	  ;; The window to reuse.
	  (list
	   :format "%v\n"
	   (const :format "" reuse-window)
	   ;; The window type.
	   (choice
	    :tag "Window"
	    :help-echo "Window to reuse."
	    :value nil
	    :format "%[Window%] %v" :size 15
	    (const :tag "Any" :format "%t" nil)
	    (const :tag "Selected only" :format "%t" same)
	    (const :tag "Any but selected" :format "%t" other))
	   ;; The window's buffer.
	   (choice
	    :tag "Buffer"
	    :help-echo "Buffer shown by reused window."
	    :value t
	    :format " %[Buffer%] %v" :size 15
	    (const :tag "Any buffer" :format "%t" nil)
	    (const :tag "Same buffer" :format "%t" same)
	    (const :tag "Other buffer" :format "%t" other))
	   ;; The window's frame.
	   (choice
	    :help-echo "Frame to search for a window to reuse."
	    :tag "Frame"
	    :value nil
	    :format " %[Frame%] %v" :size 15
	    (const :tag "Selected frame only" :format "%t" nil)
	    (const :tag "Visible frames" :format "%t" visible)
	    (const :tag "Visible but unselected" :format "%t" other)
	    (const :tag "Visible and iconified" :format "%t" 0)
	    (const :tag "Any frame" :format "%t" t)))
	  ;; Whether window sizes should be evened out.
	  (cons
	   :format "%v\n"
	   :tag "Even window sizes"
	   (const :format "" reuse-window-even-sizes)
	   (choice
	    :tag "Even window sizes"
	    :help-echo "Whether to even sizes of selected and reused window."
   	    :value t
	    :format "%[Even window sizes%] %v" :size 15
	    (const :tag "Off" :format "%t" nil)
	    (const :tag "Even window sizes" :format "%t" t)))
	  ;; Whether to reuse a dedicated window
	  (cons
	   :format "%v\n"
	   (const :format "" reuse-window-dedicated)
	   (choice
	    :tag "Reuse dedicated window" :value nil
	    :help-echo "Reuse a window even if it is dedicated to its buffer."
	    :format "%[Reuse dedicated window%] %v" :size 15
	    (const :tag "Off" :format "%t" nil)
	    (const :tag "Reuse weakly dedicated windows" :format "%t" weak)
	    (const :tag "Reuse any dedicated window" :format "%t" t)))))

	;; Pop-up window specifiers.
	(list
	 :tag "Pop-up window"
	 :value (pop-up-window (pop-up-window (largest . nil) (lru . nil)))
	 :format "%t\n%v"
	 :inline t
	 (const :format "" pop-up-window)
	 (set
	  :format "%v"
	  :inline t
	  ;; Pop-up window list.
	  (list
	   :format "%v"
	   :value (pop-up-window (largest . nil) (lru . nil))
	   (const :format "" pop-up-window)
	   (repeat
	    :tag "Window / Side tuples"
	    :inline t
	    (cons
	     :format "%v\n"
	     (choice
	      :tag "Window"
	      :help-echo "The window to split."
	      :value largest
	      :format "%[Window%] %v"
	      (const :tag "Largest" :format "%t" largest)
	      (const :tag "Least recently used" :format "%t" lru)
	      (const :tag "Selected" :format "%t" selected)
	      (const :tag "Root" :format "%t" root)
	      (const :tag "Left" :format "%t" left)
	      (const :tag "Top" :format "%t" top)
	      (const :tag "Right" :format "%t" right)
	      (const :tag "Bottom" :format "%t" bottom))
	     (choice
	      :tag "Side"
	      :help-echo "The position of the new window with respect to the window to split."
	      :value nil
	      :format " %[Side%] %v"
	      (const :tag "Dynamic" :format "%t" nil)
	      (const :tag "Below" :format "%t" below)
	      (const :tag "Right" :format "%t" right)
	      (const :tag "Above" :format "%t" above)
	      (const :tag "Left" :format "%t" left)
	      (function
	       :tag "Function" :format "%v" :size 25)))))
	  ;; Minimum height of pop-up windows.
	  (cons
	   :format "%v\n"
	   (const :format "" pop-up-window-min-height)
	   (choice
	    :help-echo "Minimum height of popped-up window."
	    :format "%[Minimum height%] %v"
	    (const :tag "Default" :format "%t" :value nil)
	    (integer :tag "Number of lines" :value 12 :size 5)
	    (float :tag "Fraction of frame height" :value .25 :size 5)))
	  ;; Minimum width of pop-up windows.
	  (cons
	   :format "%v\n"
	   (const :format "" pop-up-window-min-width)
	   (choice
	    :help-echo "Minimum width of popped-up window."
	    :format "%[Minimum width%] %v"
	    (const :tag "Default" :format "%t" :value nil)
	    (integer :tag "Number of columns" :value 12 :size 5)
	    (float :tag "Fraction of frame width" :value .25 :size 5)))
	  ;; Desired height of pop-up windows.
	  (cons
	   :format "%v\n"
	   (const :format "" pop-up-window-set-height)
	   (choice
	    :help-echo "Desired height of popped-up window."
	    :format "%[Desired height%] %v"
	    (const :tag "Default" :format "%t" :value nil)
	    (integer :tag "Number of lines" :value 12 :size 5)
	    (float :tag "Fraction of frame height" :value .25 :size 5)
	    (function :tag "Function" :size 25)))
	  ;; Desired width of pop-up windows.
	  (cons
	   :format "%v\n"
	   (const :format "" pop-up-window-set-width)
	   (choice
	    :help-echo "Desired width of popped-up window."
	    :format "%[Desired width%] %v"
	    (const :tag "Default" :format "%t" :value nil)
	    (integer :tag "Number of column" :value 12 :size 5)
	    (float :tag "Fraction of frame width" :value .25 :size 5)
	    (function :tag "Function" :size 25)))
	  ;; Split unsplittable frames.
	  (cons
	   :format "%v\n"
	   (const :format "" pop-up-window-unsplittable)
	   (choice
	    :help-echo "Allow popping up a window on \"unsplittable\" frames."
	    :format "%[Split unsplittable frame%] %v"
	    (const :tag "Off" :format "%t" nil)
	    (const :tag "Allow" :format "%t" t)))))

	;; Pop-up frame specifiers.
	(list
	 :tag "Pop-up frame"
	 :value (pop-up-frame
		 (pop-up-frame))
	 :format "%t\n%v"
	 :inline t
	 (const :format "" pop-up-frame)
	 (set
	  :format "%v"
	  :inline t
	  ;; Pop-up frame.
	  (list
	   :tag "Pop-up a new frame"
	   :value (pop-up-frame)
	   :format "%v"
	   (const :format "" pop-up-frame)
	   (choice
	    :tag "Pop-up a new frame"
	    :help-echo "Whether to pop-up a new frame on a display."
	    :format "%[Display%] %v\n" :size 15
	    (const :tag "On any display" :format "%t" nil)
	    (const :tag "On graphic displays only" :format "%t" t)))
	  ;; Pop-up frame function.
	  (cons
	   :format "%v\n"
	   (const :format "" pop-up-frame-function)
	   (choice
	    :tag "Pop-up frame function"
	    :value nil
	    :help-echo "Function to use to pop-up a new frame."
	    :format "%[Function%] %v" :size 15
	    (const :tag "Default" :format "%t" nil)
	    (function
	     :value make-frame
	     :format "%t: %v"
	     :size 25)))
	  ;; Pop-up frame alist.
	  (list
	   :format "%v"
	   (const :format "" pop-up-frame-alist)
	   (repeat
	    :tag "Parameter / Value tuples"
	    :inline t
	    (cons
	     :format "%v\n"
	     (symbol
	      :tag "Parameter"
	      :format "Parameter: %v"
	      :size 16)
	     (sexp
	      :tag "Value"
	      :format "  Value: %v"
	      :size 8))))))

	;; Use side-window specifiers.
	(list
	 :tag "Use side-window"
	 :value (use-side-window (use-side-window bottom 0))
	 :format "%t\n%v"
	 :inline t
	 ;; For customization purposes only.
	 (const :format "" use-side-window)
	 (set
	  :format "%v"
	  :inline t
	  ;; Side and slot.
	  (list
	   :format "%v\n"
	   :value (use-side-window bottom 0)
	   (const :format "" use-side-window)
	   ;; The side.
	   (choice
	    :tag "Side"
	    :help-echo "Side of frame."
	    :value bottom
	    :format "%[Side%] %v" :size 15
	    (const :tag "Left" :format "%t" left)
	    (const :tag "Top" :format "%t" top)
	    (const :tag "Right" :format "%t" right)
	    (const :tag "Bottom" :format "%t" bottom))
	   ;; The slot
	   (number
	    :tag "Slot"
	    :help-echo "The slot (an arbitrary number, where 0 stands for the center slot)."
	    :value 0
	    :format "   Slot: %v" :size 8))
	  ;; Whether to reuse a dedicated side window
	  (cons
	   :format "%v\n"
	   (const :format "" reuse-window-dedicated)
	   (choice
	    :tag "Reuse dedicated side window" :value nil
	    :help-echo "Reuse a side window even if it is dedicated to its buffer."
	    :format "%[Reuse dedicated side window%] %v" :size 15
	    (const :tag "Off" :format "%t" nil)
	    (const :tag "Reuse weakly dedicated side windows" :format "%t" weak)
	    (const :tag "Reuse any dedicated side window" :format "%t" t)))
	  ;; Minimum height of pop-up side windows.
	  (cons
	   :format "%v\n"
	   (const :format "" pop-up-window-min-height)
	   (choice
	    :help-echo "Minimum height of popped-up side window."
	    :format "%[Minimum height%] %v"
	    (const :tag "Default" :format "%t" :value nil)
	    (integer :tag "Number of lines" :value 12 :size 5)
	    (float :tag "Fraction of frame height" :value .25 :size 5)))
	  ;; Minimum width of pop-up windows.
	  (cons
	   :format "%v\n"
	   (const :format "" pop-up-window-min-width)
	   (choice
	    :help-echo "Minimum width of popped-up side window."
	    :format "%[Minimum width%] %v"
	    (const :tag "Default" :format "%t" :value nil)
	    (integer :tag "Number of columns" :value 12 :size 5)
	    (float :tag "Fraction of frame width" :value .25 :size 5)))
	  ;; Desired height of pop-up windows.
	  (cons
	   :format "%v\n"
	   (const :format "" pop-up-window-set-height)
	   (choice
	    :help-echo "Desired height of popped-up side window."
	    :format "%[Desired height%] %v"
	    (const :tag "Default" :format "%t" :value nil)
	    (integer :tag "Number of lines" :value 12 :size 5)
	    (float :tag "Fraction of frame height" :value .25 :size 5)
	    (function :tag "Function" :size 25)))
	  ;; Desired width of pop-up windows.
	  (cons
	   :format "%v\n"
	   (const :format "" pop-up-window-set-width)
	   (choice
	    :help-echo "Desired width of popped-up side window."
	    :format "%[Desired width%] %v"
	    (const :tag "Default" :format "%t" :value nil)
	    (integer :tag "Number of column" :value 12 :size 5)
	    (float :tag "Fraction of frame width" :value .25 :size 5)
	    (function :tag "Function" :size 25)))))

	;; Function with argument specifiers.
	(list
	 :tag "Function with arguments"
	 :value (fun-with-args (fun-with-args 'ignore))
	 :format "%t\n%v"
	 :inline t
	 ;; For customization purposes only.
	 (const :format "" fun-with-args)
	 (set
	  :format "%v"
	  :inline t
	  (list
	   :format "%v"
	   :value (fun-with-args 'ignore)
	   (const :format "" fun-with-args)
	   (function :tag "Function" :format "%t: %v\n" :size 25)
	   (list
	    :format "%v"
	    (repeat
	     :tag "Arguments"
	     :inline t
	     (sexp
	      :format "%v\n"
	      :size 16))))))

	;; Macro specifiers.
	(list
	 :tag "Same frame only"
	 :format "%t%v"
	 :inline t
	 (const :format "\n" same-frame))
	(list
	 :tag "Other window"
	 :format "%t%v"
	 :inline t
	 (const :format "\n" other-window))
	(list
	 :tag "Same frame other window"
	 :format "%t%v"
	 :inline t
	 (const :format "\n" same-frame-other-window))
	(list
	 :tag "Other frame only"
	 :format "%t%v"
	 :inline t
	 (const :format "\n" other-frame))
	(list
	 :tag "Default"
	 :format "%t%v"
	 :inline t
	 (const :format "\n" default)))))

     (set
      :format "%v"
      :inline t
      ;; Dedicate window to buffer.
      (cons
       :format "%v"
       (const :format "" dedicate)
       (choice
	:help-echo "Mark window as dedicated to its buffer."
	:format "%[Dedicate window to buffer%] %v\n" :size 15
	(const :tag "Off" :format "%t" nil)
	(const :tag "Weak" :format "%t" weak)
	(const :tag "Strong" :format "%t" t)))
      ;; No other window.
      (cons
       :format "%v"
       (const :format "" no-other-window)
       (choice
	:help-echo "Whether `other-window' shall ignore the window."
	:format "%[No other window%] %v\n" :size 15
	(const :tag "Off" :format "%t" nil)
	(const :tag "Ignore" :format "%t" t)))
      ;; Other window means other frame.
      (cons
       :format "%v"
       (const :format "" other-window-means-other-frame)
       (choice
	:help-echo "Whether other window means same or other frame."
	:format "%[Same or other frame%] %v\n" :size 15
	(const :tag "Same frame" :format "%t" nil)
	(const :tag "Other frame" :format "%t" t)))
      ;; Overriding.
      (cons
       :format "%v\n"
       (const :format "" override)
       (choice
	:help-echo "Override application supplied specifiers."
	:format "%[Override%] %v"
	(const :tag "Off" :format "%t" nil)
	(const :tag "Override" :format "%t" t))))))
  :group 'windows
  :group 'frames)

(defcustom display-buffer-function nil
  "If non-nil, function to call to display a buffer.
`display-buffer' calls this function with two arguments, the
buffer to display and a list of buffer display specifiers, see
`display-buffer-alist'.

The function is supposed to choose or create a window, display
the specified buffer in it, and return the window.  It is also
responsible for giving the variable `display-buffer-window' and
the `quit-restore' parameter of the window used a meaningful
value.

The function specified here overrides all specifiers of the
variable `display-buffer-alist' any specifiers passed to
`display-buffer'.

If you call `display-buffer' within the body of the function,
bind the value of `display-buffer-function' to nil around that
call to avoid that the function recursively calls itself."
  :type '(choice
	  (const nil)
	  (function :tag "Function"))
  :group 'windows)

;; The following is a global variable which is used externally (by
;; help.el) to (1) know which window was used for displaying a buffer
;; and (2) whether the window was new or reused.
(defvar display-buffer-window nil
  "Window used by `display-buffer' and related information.
After `display-buffer' displays a buffer in some window this
variable is a cons cell whose car denotes the window used to
display the buffer.  The cdr is supposed to be one of the symbols
`reuse-buffer-window', `reuse-other-window', `new-window' or
`new-frame'.

If the buffer display location specifier is one of 'same-window,
'same-frame, or 'other-frame, the `display-buffer' routines
assign the value of this variable.  If the location specifier is
a function, that function becomes responsible for assigning a
meaningful value to this variable.  See the functions
`display-buffer-reuse-window', `display-buffer-pop-up-window' and
`display-buffer-pop-up-frame' for how this can be done.")

(defun display-buffer-even-window-sizes (window specifiers)
  "Even sizes of WINDOW and selected window according to SPECIFIERS.
SPECIFIERS must be a list of buffer display specifiers, see the
documentation of `display-buffer-alist' for a description.

Sizes are evened out if and only if WINDOW and the selected
window appear next to each other and the selected window is
larger than WINDOW."
  (cond
   ((or (not (cdr (assq 'reuse-window-even-sizes specifiers)))
	;; Don't resize minibuffer windows.
	(window-minibuffer-p)
	;; WINDOW must be adjacent to the selected one.
	(not (or (eq window (window-prev))
		 (eq window (window-next))))))
   ((and (window-iso-combined-p window)
	 ;; Resize iff the selected window is higher than WINDOW.
	 (> (window-total-height) (window-total-height window)))
    ;; Don't throw an error if we can't even window heights for
    ;; whatever reason.  In any case, enlarging the selected window
    ;; might fail anyway if there are other windows above or below
    ;; WINDOW and the selected one.  But for a simple two windows
    ;; configuration the present behavior is good enough so why care?
    (ignore-errors
      (resize-window
       window (/ (- (window-total-height) (window-total-height window))
		 2))))
   ((and (window-iso-combined-p window t)
	 ;; Resize iff the selected window is wider than WINDOW.
	 (> (window-total-width) (window-total-width window)))
    ;; Don't throw an error if we can't even window widths, see
    ;; comment above.
    (ignore-errors
      (resize-window
       window (/ (- (window-total-width) (window-total-width window))
		 2) t)))))

(defun display-buffer-set-height (window specifiers)
  "Adjust height of WINDOW according to SPECIFIERS.
SPECIFIERS must be a list of buffer display specifiers, see the
documentation of `display-buffer-alist' for a description."
  (let ((set-height (cdr (assq 'pop-up-window-set-height specifiers))))
    (cond
     ((numberp set-height)
      (let* ((height (if (integerp set-height)
			 set-height
		       (round
			(* (window-total-size (frame-root-window window))
			   set-height))))
	     (delta (- height (window-total-size window))))
	(when (and (window-resizable-p window delta nil 'safe)
		   (window-iso-combined-p window))
	  (resize-window window delta nil 'safe))))
     ((functionp set-height)
      (ignore-errors (funcall set-height window))))))

(defun display-buffer-set-width (window specifiers)
  "Adjust width of WINDOW according to SPECIFIERS.
SPECIFIERS must be a list of buffer display specifiers, see the
documentation of `display-buffer-alist' for a description."
  (let ((set-width (cdr (assq 'pop-up-window-set-width specifiers))))
    (cond
     ((numberp set-width)
      (let* ((width (if (integerp set-width)
			set-width
		      (round
		       (* (window-total-size (frame-root-window window) t)
			  set-width))))
	     (delta (- width (window-total-size window t))))
	(when (and (window-resizable-p window delta t 'safe)
		   (window-iso-combined-p window t))
	  (resize-window window delta t 'safe))))
     ((functionp set-width)
      (ignore-errors (funcall set-width window))))))

(defun display-buffer-in-window (buffer window specifiers)
  "Display BUFFER in WINDOW and raise its frame if needed.
WINDOW must be a live window and defaults to the selected one.
Return WINDOW.

SPECIFIERS must be a list of buffer display specifiers, see the
documentation of `display-buffer-alist' for a description."
  (setq buffer (normalize-live-buffer buffer))
  (setq window (normalize-live-window window))
  (let* ((old-frame (selected-frame))
	 (new-frame (window-frame window))
	 (dedicated (cdr (assq 'dedicated specifiers)))
	 (no-other-window (cdr (assq 'no-other-window specifiers))))
    ;; Show BUFFER in WINDOW.
    (set-window-dedicated-p window nil)
    (set-window-buffer window buffer)
    (when dedicated
      (set-window-dedicated-p window dedicated))
    (when no-other-window
      (set-window-parameter window 'no-other-window t))
    (unless (or (eq old-frame new-frame)
		(not (frame-visible-p new-frame))
		;; Assume the selected frame is already visible enough.
		(eq new-frame (selected-frame))
		;; Assume the frame from which we invoked the minibuffer
		;; is visible.
		(and (minibuffer-window-active-p (selected-window))
		     (eq new-frame
			 (window-frame (minibuffer-selected-window)))))
      (raise-frame new-frame))
    ;; Return window.
    window))

(defun display-buffer-reuse-window (buffer method &optional specifiers)
  "Display BUFFER in an existing window.
METHOD must be a list in the form of the cdr of a `reuse-window'
buffer display specifier, see `display-buffer-alist' for an
explanation.  The first element must specifiy the window to use,
and can be either nil, `same', `other', or a live window.  The
second element must specify the window's buffer and can be either
nil, `same', `other', or a live buffer.  The third element is the
frame to use - either nil, 0, `visible', `other', t, or a live
frame.

Optional argument SPECIFIERS must be a list of valid display
specifiers.  Return the window chosen to display BUFFER, nil if
none was found."
  (let* ((method-window (nth 0 method))
	 (method-buffer (nth 1 method))
	 (method-frame (nth 2 method))
	 (reuse-dedicated (assq 'reuse-window-dedicated specifiers))
	 windows other-frame dedicated time best-window best-time)
    (when (eq method-frame 'other)
      ;; `other' is not handled by `window-list-1'.
      (setq other-frame t)
      (setq method-frame t))
    (dolist (window (window-list-1 nil 'nomini method-frame))
      (let ((window-buffer (window-buffer window)))
	(when (and (not (window-minibuffer-p window))
		   ;; Don't reuse a side window.
		   (or (not (eq (window-parameter window 'window-side) 'side))
		       (eq window-buffer buffer))
		   (or (not method-window)
		       (and (eq method-window 'same)
			    (eq window (selected-window)))
		       (and (eq method-window 'other)
			    (not (eq window (selected-window))))
		       ;; Special case for applications that specifiy
		       ;; the window explicitly.
		       (eq method-window window))
		   (or (not method-buffer)
		       (and (eq method-buffer 'same)
			    (eq window-buffer buffer))
		       (and (eq method-buffer 'other)
			    (not (eq window-buffer buffer)))
		       ;; Special case for applications that specifiy
		       ;; the window's buffer explicitly.
		       (eq method-buffer window-buffer))
		   (or (not other-frame)
		       (not (eq (window-frame window) (selected-frame))))
		   ;; Handle dedicatedness.
		   (or (eq window-buffer buffer)
		       ;; The window does not show the same buffer.
		       (not (setq dedicated (window-dedicated-p window)))
		       ;; If the window is weakly dedicated to its
		       ;; buffer, reuse-dedicated must be non-nil.
		       (and (not (eq dedicated t)) reuse-dedicated)
		       ;; If the window is strongly dedicated to its
		       ;; buffer, reuse-dedicated must be t.
		       (eq reuse-dedicated t)))
	  (setq windows (cons window windows)))))

    (if (eq method-buffer 'same)
	;; When reusing a window on the same buffer use the lru one.
	(dolist (window windows)
	  (setq time (window-use-time window))
	  (when (or (not best-window) (< time best-time))
	    (setq best-window window)
	    (setq best-time time)))
      ;; Otherwise, sort windows according to their use-time.
      (setq windows
	    (sort windows
		  #'(lambda (window-1 window-2)
		      (<= (window-use-time window-1)
			  (window-use-time window-2)))))
      (setq best-window
	    ;; Try to get a full-width window (this is silly and can
	    ;; get us to another frame but let's ignore these issues
	    ;; for the moment).
	    (catch 'found
	      (dolist (window windows)
		(when (window-full-width-p window)
		  (throw 'found window)))
	      ;; If there's no full-width window return the lru window.
	      (car windows))))

    (when best-window
      (display-buffer-even-window-sizes best-window specifiers)
      ;; Never change the quit-restore parameter of a window here.
      (if (eq (window-buffer best-window) buffer)
	  (setq display-buffer-window
		(cons best-window 'reuse-buffer-window))
	(setq display-buffer-window
	      (cons best-window 'reuse-other-window))
	(unless (window-parameter best-window 'quit-restore)
	  ;; Don't overwrite an existing quit-restore entry.
	  (set-window-parameter
	   best-window 'quit-restore
	   (list (window-buffer best-window) (window-start best-window)
		 (window-point best-window) buffer
		 (window-total-size best-window) (selected-window)))))

      (display-buffer-in-window buffer best-window specifiers))))

(defconst display-buffer-split-specifiers '(largest lru selected root left top right bottom)
  "List of symbols identifying window that shall be split.")

(defconst display-buffer-side-specifiers '(below right above left nil)
  "List of symbols identifying side of split-off window.")

(defun display-buffer-split-window-1 (window side min-size)
  "Subroutine of `display-buffer-split-window'."
  (let* ((horizontal (memq side '(left right)))
	 (parent (window-parent window))
	 (resize (and window-splits (window-iso-combined-p window horizontal)))
	 (old-size
	  ;; We either resize WINDOW or its parent.
	  (window-total-size (if resize parent window) horizontal))
	 new-size)
    ;; We don't call split-window-vertically/-horizontally any more
    ;; here. If for some reason it's needed we can always do so
    ;; (provided we give it an optional SIDE argument).
    (cond
     (resize
      ;; When we resize a combination, the new window must be at least
      ;; MIN-SIZE large after the split.
      (setq new-size
	    (max min-size
		 (min (- old-size (window-min-size parent horizontal))
		      (/ old-size
			 ;; Try to make the size of the new window
			 ;; proportional to the number of iso-arranged
			 ;; windows in the combination.
			 (1+ (window-iso-combinations parent horizontal))))))
      (when (window-sizable-p parent (- new-size) horizontal)
	(split-window window (- new-size) side)))
     ((window-live-p window)
      (setq new-size (/ old-size 2))
      ;; When WINDOW is live, the old _and_ the new window must be at
      ;; least MIN-SIZE large after the split.
      (when (and (>= new-size min-size)
		 (window-sizable-p window (- new-size) horizontal))
	;; Do an even split to make Stepan happy.
	(split-window window nil side)))
     (t
      ;; When WINDOW is internal, the new window must be at least
      ;; MIN-SIZE large after the split.
      (setq new-size
	    (max min-size
		 (/ old-size
		    ;; Try to make the size of the new window
		    ;; proportional to the number of iso-arranged
		    ;; subwindows of WINDOW.
		    (1+ (window-iso-combinations window horizontal)))))
      (when (window-sizable-p window (- new-size) horizontal)
	(split-window window (- new-size) side))))))

(defun display-buffer-split-window (window &optional side specifiers)
  "Split WINDOW in a way suitable for `display-buffer'.
Optional argument SIDE must be a side specifier \(one of the
symbols below, right, above, left, or nil).  SPECIFIERS must be a
list of buffer display specifiers, see the documentation of
`display-buffer-alist' for a description.

Return the new window, nil if it could not be created."
  (let ((min-height (cdr (assq 'pop-up-window-min-height specifiers)))
	(min-width (cdr (assq 'pop-up-window-min-width specifiers)))
	size)
    ;; Normalize min-height and min-width, we might need both.
    (setq min-height
	  ;; If min-height is specified, it can be as small as
	  ;; `window-safe-min-height'.
	  (cond
	   ((and (integerp min-height)
		 (>= min-height window-safe-min-height))
	    min-height)
	   ((and (floatp min-height)
		 (<= min-height 1)
		 (let* ((root-height (window-total-height
				      (frame-root-window
				       (window-frame window))))
			(height (round (* min-height root-height))))
		   (when (>= height window-safe-min-height)
		     height))))
	   (t window-min-height)))
    (setq min-width
	  ;; If min-width is specified, it can be as small as
	  ;; `window-safe-min-width'.
	  (cond
	   ((and (integerp min-width)
		 (>= min-width window-safe-min-width))
	    min-width)
	   ((and (floatp min-width)
		 (<= min-width 1)
		 (let* ((root-width (window-total-width
				     (frame-root-window
				      (window-frame window))))
			(width (round (* min-width root-width))))
		   (when (>= width window-safe-min-width)
		     width))))
	   (t window-min-width)))

    (or (and (memq side '(nil above below))
	     (display-buffer-split-window-1
	      window (or side 'below) min-height))
	;; If SIDE is nil and vertical splitting failed, we try again
	;; splitting horizontally this time.
	(and (memq side '(nil left right))
	     (display-buffer-split-window-1
	      window (or side 'right) min-width))
	;; If WINDOW is live and the root window of its frame, try once
	;; more splitting vertically, disregarding the min-height
	;; specifier this time and using `window-min-height' instead.
	(and (memq side '(nil above below))
	     (<= window-min-height min-height)
	     (window-live-p window)
	     (eq window (frame-root-window window))
	     (display-buffer-split-window-1
	      window (or side 'below) window-min-height)))))

(defun display-buffer-split-atom-window (window &optional side nest specifiers)
  "Make WINDOW part of an atomic window."
  (let ((ignore-window-parameters t)
	(window-nest t)
	(selected-window (selected-window))
	root new new-parent)

      ;; We are in an atomic window.
    (when (and (window-parameter window 'window-atom) (not nest))
      ;; Split the root window.
      (setq window (window-atom-root window)))

    (when (setq new (display-buffer-split-window window side specifiers))
      (setq new-parent (window-parent window))
      ;; WINDOW is or becomes atomic.
      (unless (window-parameter window 'window-atom)
	(walk-window-subtree
	 (lambda (window)
	   (set-window-parameter window 'window-atom t))
	 window t))
      ;; New window and any new parent get their window-atom parameter
      ;; set too.
      (set-window-parameter new 'window-atom t)
      (set-window-parameter new-parent 'window-atom t)
      new)))

(defun display-buffer-pop-up-window (buffer methods &optional specifiers)
  "Display BUFFER in a new window.
Return the window displaying BUFFER, nil if popping up the window
failed.  METHODS must be a list of window/side tuples like those
forming the cdr of the `pop-up-window' buffer display specifier.
As a special case, the car of such a tuple can be also a live
window.

Optional argument SPECIFIERS must be a list of buffer display
specifiers, see the doc-string of `display-buffer-alist' for a
description."
  (let* ((frame (display-buffer-frame))
	 (selected-window (frame-selected-window frame))
	 window side atomic)
    (unless (and (cdr (assq 'unsplittable (frame-parameters frame)))
		 ;; Don't split an unsplittable frame unless
		 ;; SPECIFIERS allow it.
		 (not (cdr (assq 'split-unsplittable-frame specifiers))))
      (catch 'done
	(dolist (method methods)
	  (setq window (car method))
	  (setq side (cdr method))
	  (and (setq window
		     (cond
		      ((eq window 'largest)
		       (get-largest-window frame t))
		      ((eq window 'lru)
		       (get-lru-window frame t))
		      ((eq window 'selected)
		       (frame-selected-window frame))
		      ((eq window 'root)
		       ;; If there are side windows, split the main
		       ;; window else the frame root window.
		       (or (window-with-parameter 'window-side 'none nil t)
			   (frame-root-window frame)))
		      ((memq window window-sides)
		       ;; This should gets us the "root" side
		       ;; window if there exists more than one.
		       (window-with-parameter 'window-side window nil t))
		      ((windowp window)
		       ;; A window, directly specified.
		       window)))
	       ;; The window must be on the selected frame,
	       (eq (window-frame window) frame)
	       ;; and must be neither a minibuffer window,
	       (not (window-minibuffer-p window))
	       ;; nor a side window.
	       (not (eq (window-parameter window 'window-side) 'side))
	       (setq window
		     (cond
		      ((memq side display-buffer-side-specifiers)
		       (if (and (window-buffer window)
				(setq atomic (cdr (assq 'atomic specifiers))))
			   (display-buffer-split-atom-window
			    window side (eq atomic 'nest) specifiers)
		       (display-buffer-split-window window side specifiers)))
		      ((functionp side)
		       (ignore-errors
			 ;; Don't pass any specifiers to this function.
			 (funcall side window)))))
	       (throw 'done window))))

      (when window
	;; Adjust sizes if asked for.
	(display-buffer-set-height window specifiers)
	(display-buffer-set-width window specifiers)
	(set-window-parameter
	 window 'quit-restore (list 'new-window buffer selected-window))
	(setq display-buffer-window (cons window 'new-window))
	(display-buffer-in-window buffer window specifiers)
	(set-window-prev-buffers window nil)
	window))))

(defun display-buffer-pop-up-frame (buffer &optional graphic-only specifiers)
  "Make a new frame for displaying BUFFER.
Return the window displaying BUFFER if creating the new frame was
successful, nil otherwise.  Optional argument GRAPHIC-ONLY
non-nil means to make a new frame on graphic displays only.

SPECIFIERS must be a list of buffer display specifiers, see the
documentation of `display-buffer-alist' for a description."
  (unless (or (and graphic-only (not (display-graphic-p)))
	      noninteractive)
    (let* ((selected-window (selected-window))
	   (function (or (cdr (assq 'pop-up-frame-function specifiers))
			 'make-frame))
	   (parameters
	    (when (symbolp function)
	      (cdr (assq 'pop-up-frame-alist specifiers))))
	   (frame
	    (if (symbolp function)
		(funcall function parameters)
	      (funcall function))))
      (when frame
	(let ((window (frame-selected-window frame)))
	  (set-window-parameter
	   window 'quit-restore (list 'new-frame buffer selected-window))
	  (setq display-buffer-window (cons window 'new-frame))
	  (display-buffer-in-window buffer window specifiers))))))

(defun display-buffer-pop-up-side-window (buffer side slot &optional specifiers)
  "Display BUFFER in a new window on SIDE of the selected frame.
SLOT specifies the slot to use.  SPECIFIERS must be a list of
buffer display specifiers.

Return the window displaying BUFFER, nil if popping up the window
failed."
  (let* ((root (frame-root-window))
	 (main (window-with-parameter 'window-side 'none nil t))
	 (left-or-right (memq side '(left right)))
	 (main-or-root
	  (if (and main
		   (or (and left-or-right (not window-sides-vertical))
		       (and (not left-or-right) window-sides-vertical)))
	      main
	    root))
	 (selected-window (selected-window))
	 (on-side (cond
		   ((eq side 'top) 'above)
		   ((eq side 'bottom) 'below)
		   (t side)))
	 (window
	  (display-buffer-split-window main-or-root on-side specifiers))
	 fun)
    (when window
      (unless main
	(walk-window-subtree
	 (lambda (window)
	   ;; Make all main-or-root subwindows main windows.
	   (set-window-parameter window 'window-side 'none))
	 main-or-root t))
      ;; Make sure that parent's window-side is nil.
      (set-window-parameter (window-parent window) 'window-side nil)
      ;; Initialize side.
      (set-window-parameter window 'window-side side)
      ;; Adjust sizes if asked for.
      (display-buffer-set-height window specifiers)
      (display-buffer-set-width window specifiers)
      ;; Set window parameters.
      (set-window-parameter
       window 'quit-restore (list 'new-window buffer selected-window))
      (setq display-buffer-window (cons window 'new-window))
      (set-window-parameter window 'window-slot slot)
      (display-buffer-in-window buffer window specifiers)
      (set-window-prev-buffers window nil)
      window)))

(defun display-buffer-in-side-window (buffer side &optional slot specifiers)
  "Display BUFFER in a window on SIDE of the selected frame.
SLOT, if non-nil, specifies the window slot where to display the
BUFFER.  SLOT zero or nil means use the central slot on SIDE.
SLOT negative means use a slot preceding the central window.
SLOT positive means use a slot following the central window.

SPECIFIERS must be a list of buffer display specifiers."
  (unless (memq side window-sides)
    (error "Invalid side %s specified" side))
  (let* ((major (window-with-parameter 'window-side side nil t))
	 ;; `major' is the major window on SIDE, `windows' the life
	 ;; windows on SIDE.
	 (windows (when major (windows-with-parameter 'window-side side)))
	 (slots (when major (window-child-count major)))
	 (max-slots
	  (nth (cond
		((eq side 'left) 0)
		((eq side 'top) 1)
		((eq side 'right) 2)
		((eq side 'bottom) 3))
		window-sides-slots))
	 (selected-window (selected-window))
	 window this-window this-slot prev-window next-window
	 best-window best-slot abs-slot)

    (unless (numberp slot)
      (setq slot 0))
    (if (not windows)
	;; No suitable side window exists, make one.
	(display-buffer-pop-up-side-window buffer side slot specifiers)
      ;; Scan windows on SIDE.
      (catch 'found
	(dolist (window windows)
	  (setq this-slot (window-parameter window 'window-slot))
	  (cond
	   ((not (numberp this-slot)))
	   ((and (= this-slot slot)
		 ;; Dedicatedness check.
		 (or (not (window-dedicated-p window))
		     (assq 'reuse-window-dedicated specifiers)))
	    ;; Window with matching SLOT, use it.
	    (setq this-window window)
	    (throw 'found t))
	   (t
	    (setq abs-slot (abs (- (abs slot) (abs this-slot))))
	    (unless (and best-slot (<= best-slot abs-slot))
	      (setq best-window window)
	      (setq best-slot abs-slot))
	    (cond
	     ((<= this-slot slot)
	      (setq prev-window window))
	     ((not next-window)
	      (setq next-window window)))))))

      ;; `this-window' is the first window with the same SLOT.
      ;; `prev-window' is the window with the largest slot < SLOT.  A new
      ;; window will be created after it.
      ;; `next-window' is the window with the smallest slot > SLOT.  A new
      ;; window will be created before it.
      ;; `best-window' is the window with the smallest absolute difference
      ;; of its slot and SLOT.
      (or (and this-window
	       ;; Reuse this window.
	       (prog1
		   (setq window this-window)
		 (if (eq (window-buffer window) buffer)
		     (setq display-buffer-window
			   (cons window 'reuse-buffer-window))
		   (setq display-buffer-window
			 (cons window 'reuse-other-window))
		   (unless (window-parameter window 'quit-restore)
		     ;; Don't overwrite an existing quit-restore entry.
		     (set-window-parameter
		      window 'quit-restore
		      (list (window-buffer window) (window-start window)
			    (window-point window) buffer
			    (window-total-size window) (selected-window)))))))
	  (and (or (not max-slots) (< slots max-slots))
	       (or (and next-window
			;; Make new window before next-window.
			(let ((next-side
			       (if (memq side '(left right)) 'above 'left)))
			  (setq window (display-buffer-split-window
					next-window next-side specifiers))))
		   (and prev-window
			;; Make new window after prev-window.
			(let ((prev-side
			       (if (memq side '(left right)) 'below 'right)))
			  (setq window (display-buffer-split-window
					prev-window prev-side specifiers)))))
	       (progn
		 (display-buffer-set-height window specifiers)
		 (display-buffer-set-width window specifiers)
		 (set-window-parameter
		  window 'quit-restore
		  (list 'new-window buffer selected-window))
		 (setq display-buffer-window (cons window 'new-window))
		 window))
	  (and best-window
	       (setq window best-window)
	       ;; Reuse best window (the window nearest to SLOT).
	       (if (eq (window-buffer window) buffer)
		   (setq display-buffer-window
			 (cons window 'reuse-buffer-window))
		 (setq display-buffer-window
		       (cons window 'reuse-other-window))

		 (unless (window-parameter window 'quit-restore)
		   ;; Don't overwrite an existing quit-restore entry.
		   (set-window-parameter
		    window 'quit-restore
		    (list (window-buffer window) (window-start window)
			  (window-point window) buffer
			  (window-total-size window) (selected-window)))))
	       window))

      (when window
	(unless (window-parameter window 'window-slot)
	  ;; Don't change exisiting slot value.
	  (set-window-parameter window 'window-slot slot))
	(display-buffer-in-window buffer window specifiers)))))

(defun normalize-buffer-to-display (buffer-or-name)
  "Normalize BUFFER-OR-NAME argument for buffer display functions.
If BUFFER-OR-NAME is nil, return the curent buffer.  Else, if a
buffer specified by BUFFER-OR-NAME exists, return that buffer.
If no such buffer exists, create a buffer with the name
BUFFER-OR-NAME and return that buffer."
  (if buffer-or-name
      (or (get-buffer buffer-or-name)
	  (let ((buffer (get-buffer-create buffer-or-name)))
	    (set-buffer-major-mode buffer)
	    buffer))
    (current-buffer)))

(defun display-buffer-other-window-means-other-frame (buffer-or-name &optional label)
  "Return non-nil if BUFFER shall be preferably displayed in another frame.
BUFFER must be a live buffer or the name of a live buffer.

Return nil if BUFFER shall be preferably displayed in another
window on the selected frame.  Return non-nil if BUFFER shall be
preferably displayed in a window on any but the selected frame.

Optional argument LABEL is like the same argument of
`display-buffer'.

The calculation of the return value is exclusively based on the
user preferences expressed in `display-buffer-alist'."
  (let* ((buffer (normalize-live-buffer buffer-or-name))
	 (list (display-buffer-normalize-alist (buffer-name buffer) label))
	 (value (assq 'other-window-means-other-frame
		      (or (car list) (cdr list)))))
    (when value (cdr value))))

(defun display-buffer-normalize-argument (buffer-name specifiers label other-frame)
  "Normalize second argument of `display-buffer'.
BUFFER-NAME is the name of the buffer that shall be displayed,
SPECIFIERS is the second argument of `display-buffer'.  LABEL the
same argument of `display-buffer'.  OTHER-FRAME non-nil means use
other-frame for other-window."
  (let (normalized entry)
    (cond
     ((not specifiers)
      nil)
     ((listp specifiers)
      ;; If SPECIFIERS is a list, we assume it is a list of specifiers.
      (dolist (specifier specifiers)
	(cond
	 ((consp specifier)
	  (setq normalized (cons specifier normalized)))
	 ((eq specifier 'other-window)
	  ;; `other-window' must be treated separately.
	  (let ((entry (assq (if other-frame
				 'other-frame
			       'same-frame-other-window)
			     display-buffer-macro-specifiers)))
	    (dolist (item (cdr entry))
	      (setq normalized (cons item normalized)))))
	 ((symbolp specifier)
	  ;; Might be a macro specifier, try to expand it (the cdr is a
	  ;; list and we have to reverse it later, so do it one at a
	  ;; time).
	  (let ((entry (assq specifier display-buffer-macro-specifiers)))
	    (dolist (item (cdr entry))
	      (setq normalized (cons item normalized)))))))
      ;; Reverse list.
      (nreverse normalized))
     ((setq entry (assq specifiers display-buffer-macro-specifiers))
      ;; A macro specifier.
      (cdr entry))
     ((or other-frame (with-no-warnings pop-up-frames))
      ;; Pop up another frame.
      (cdr (assq 'other-frame display-buffer-macro-specifiers)))
     (t
      ;; In any other case pop up a new window.
      (cdr (assq 'same-frame-other-window display-buffer-macro-specifiers))))))

(defun display-buffer-normalize-options (buffer-or-name)
  "Subroutine of `display-buffer-normalize-specifiers'.
BUFFER-OR-NAME is the buffer to display.  This routine provides a
compatibility layer for the now obsolete Emacs 23 buffer display
options."
  (with-no-warnings
    (let* ((buffer (normalize-live-buffer buffer-or-name))
	   (buffer-name (buffer-name buffer))
	   (use-pop-up-frames
	    (or (and (eq pop-up-frames 'graphic-only)
		     (display-graphic-p))
		pop-up-frames))
	   specifiers)
      ;; `even-window-heights', unless nil or unset.
      (unless (memq even-window-heights '(nil unset))
	(setq specifiers
	      (cons (cons 'reuse-window-even-sizes t) specifiers)))

      ;; `display-buffer-mark-dedicated'
      (when display-buffer-mark-dedicated
	(setq specifiers
	      (cons (cons 'dedicate display-buffer-mark-dedicated)
		    specifiers)))

      ;; `pop-up-window' group.  Anything is added here iff
      ;; `pop-up-windows' is neither nil nor unset.
      (let ((pop-up-window (not (memq pop-up-windows '(nil unset))))
	    (fun (unless (eq split-window-preferred-function
			     'split-window-sensibly)
		   split-window-preferred-function))
	    (min-height (if (numberp split-height-threshold)
			    (/ split-height-threshold 2)
			  1.0))
	    (min-width (if (numberp split-width-threshold)
			   (/ split-width-threshold 2)
			 1.0)))
	;; Create an entry only if a default value was changed.
	(when (or pop-up-window
		  (not (equal split-height-threshold 80))
		  (not (equal split-width-threshold 160)))
	  ;; `reuse-window' (needed as fallback when popping up the new
	  ;; window fails).
	  (setq specifiers
		(cons (list 'reuse-window 'other nil nil)
		      specifiers))
	  ;; `split-width-threshold'
	  (setq specifiers
		(cons (cons 'pop-up-window-min-width min-width)
		      specifiers))
	  ;; `split-height-threshold'
	  (setq specifiers
		(cons (cons 'pop-up-window-min-height min-height)
		      specifiers))
	  ;; `pop-up-window'
	  (setq specifiers
		(cons (list 'pop-up-window
			    (cons 'largest fun) (cons 'lru fun))
		      specifiers))))

      ;; `pop-up-frame' group.
      (when use-pop-up-frames
	;; `pop-up-frame-function'.  If `pop-up-frame-function' uses the
	;; now obsolete `pop-up-frame-alist' it will continue to do so.
	(setq specifiers
	      (cons (cons 'pop-up-frame-function pop-up-frame-function)
		    specifiers))
	;; `pop-up-frame'
	(setq specifiers
	      (cons (list 'pop-up-frame t) specifiers)))

      ;; `pop-up-windows' and `use-pop-up-frames' both nil means means
      ;; we are supposed to reuse any window on the same frame (unless
      ;; we find one showing the same buffer already).
      (unless (or pop-up-windows use-pop-up-frames)
	;; `reuse-window' showing any buffer on same frame.
	(setq specifiers
	      (cons (list 'reuse-window nil nil nil)
		    specifiers)))

      ;; `special-display-p' group.
      (when special-display-function
	;; `special-display-p' returns either t or a list of frame
	;; parameters to pass to `special-display-function'.
	(let ((pars (special-display-p buffer-name)))
	  (when pars
	    (setq specifiers
		  (cons (list 'fun-with-args special-display-function
			      (when (listp pars) pars))
			specifiers)))))

      ;; `pop-up-frames', `display-buffer-reuse-frames' means search for
      ;; a window showing the buffer on some visible or iconfied frame.
      ;; `last-nonminibuffer-frame' set and not the same frame means
      ;; search that frame.
      (let ((frames (or (and (or use-pop-up-frames
				 display-buffer-reuse-frames
				 (not (last-nonminibuffer-frame)))
			     ;; All visible or iconfied frames.
			     0)
			;; Same frame.
			(last-nonminibuffer-frame))))
	(when frames
	  (setq specifiers
		(cons (list 'reuse-window 'other 'same frames)
		      specifiers))))

      ;; `same-window-p' group.
      (when (same-window-p buffer-name)
	;; Try to reuse the same (selected) window.
	(setq specifiers
	      (cons (list 'reuse-window 'same nil nil)
		    specifiers)))

      ;; Prepend "reuse window on same frame if showing the buffer
      ;; already" specifier.  It will be overriden by the application
      ;; supplied 'other-window specifier.
      (setq specifiers (cons (list 'reuse-window nil 'same nil)
			     specifiers))

      specifiers)))

(defun display-buffer-normalize-alist-1 (specifiers label)
  "Subroutine of `display-buffer-normalize-alist'.
SPECIFIERS is a list of buffer display specfiers.  LABEL is the
same argument of `display-buffer'."
  (let (normalized entry)
    (cond
     ((not specifiers)
      nil)
     ((listp specifiers)
      ;; If SPECIFIERS is a list, we assume it is a list of specifiers.
      (dolist (specifier specifiers)
	(cond
	 ((consp specifier)
	  (setq normalized (cons specifier normalized)))
	 ((symbolp specifier)
	  ;; Might be a macro specifier, try to expand it (the cdr is a
	  ;; list and we have to reverse it later, so do it one at a
	  ;; time).
	  (let ((entry (assq specifier display-buffer-macro-specifiers)))
	    (dolist (item (cdr entry))
	      (setq normalized (cons item normalized)))))))
      ;; Reverse list.
      (nreverse normalized))
     ((setq entry (assq specifiers display-buffer-macro-specifiers))
      ;; A macro specifier.
      (cdr entry)))))

(defun display-buffer-normalize-alist (buffer-name label)
  "Normalize `display-buffer-alist'.
BUFFER-NAME must be the name of the buffer that shall be displayed.
LABEL the corresponding argument of `display-buffer'."
  (let (list-1 list-2)
    (dolist (entry display-buffer-alist)
      (when (and (listp entry)
		 (catch 'match
		   (dolist (id (car entry))
		     (when (consp id)
		       (let ((type (car id))
			     (value (cdr id)))
			 (when (or (and (eq type 'name) (stringp value)
					(equal value buffer-name))
				   (and (eq type 'regexp) (stringp value)
					(string-match-p value buffer-name))
				   (and (eq type 'label) (eq value label)))
			   (throw 'match t)))))))
	(let* ((specifiers (cdr entry))
	       (normalized
		(display-buffer-normalize-alist-1 specifiers label)))
	  (if (assq 'override specifiers)
	      (setq list-1
		    (if list-1
			(append list-1 normalized)
		      normalized))
	    (setq list-2
		  (if list-2
		      (append list-2 normalized)
		    normalized))))))

    (cons list-1 list-2)))

(defvar display-buffer-normalize-options-inhibit nil
  "If non-nil, `display-buffer' doesn't process obsolete options.")

(defun display-buffer-normalize-specifiers (buffer-name specifiers label)
  "Return normalized specifiers for a buffer matching BUFFER-NAME or LABEL.
BUFFER-NAME must be a string specifying a valid buffer name.
SPECIFIERS and LABEL are the homonymous arguments of
`display-buffer'.

The method for displaying the buffer specified by BUFFER-NAME or
LABEL is established by appending the following four lists of
specifiers:

- The specifiers in `display-buffer-alist' whose buffer
  identifier matches BUFFER-NAME or LABEL and whose 'override
  component is set.

- SPECIFIERS.

- The specifiers in `display-buffer-alist' whose buffer
  identifier matches BUFFER-NAME or LABEL and whose 'override
  component is not set.

- `display-buffer-default-specifiers'."
  (let* ((list (display-buffer-normalize-alist buffer-name label))
	 (other-frame (assq 'other-window-means-other-frame
			    (or (car list) (cdr list)))))
    (append
     ;; Overriding user specifiers.
     (car list)
     ;; Application specifiers.
     (display-buffer-normalize-argument
      buffer-name specifiers label other-frame)
     ;; Emacs 23 compatibility specifiers.
     (unless display-buffer-normalize-options-inhibit
       (display-buffer-normalize-options buffer-name))
     ;; Non-overriding user specifiers.
     (cdr list)
     ;; Default specifiers.
     display-buffer-default-specifiers)))

;; Minibuffer-only frames should be documented better.  They really
;; deserve a separate section in the manual.  Also
;; `last-nonminibuffer-frame' is nowhere documented in the manual.
(defun display-buffer-frame (&optional frame)
  "Return FRAME if it is live and not a minibuffer-only frame.
Return the value of `last-nonminibuffer-frame' otherwise."
  (setq frame (normalize-live-frame frame))
  (if (and (frame-live-p frame)
	   ;; A not very nice way to get that information.
	   (not (window-minibuffer-p (frame-root-window frame))))
      frame
    (last-nonminibuffer-frame)))

(defun display-buffer (&optional buffer-or-name specifiers label)
  "Make the buffer specified by BUFFER-OR-NAME appear in some window.
Optional argument BUFFER-OR-NAME may be a buffer, a string \(a
buffer name), or nil.  If BUFFER-OR-NAME is a string not naming
an existent buffer, create a buffer with that name.  If
BUFFER-OR-NAME is nil or omitted, display the current buffer.
Interactively, prompt for the buffer name using the minibuffer.

Return the window chosen to display the buffer or nil if no such
window is found.  Do not change the selected window unless the
buffer is shown on a different frame than the selected one.

Optional argument SPECIFIERS must be a list of buffer display
specifiers, see the documentation of `display-buffer-alist' for a
description.

For convenience, SPECIFIERS may also consist of a single buffer
display location specifier or t, where the latter means to
display the buffer in any but the selected window.  If SPECIFIERS
is nil or omitted, this means to exclusively use the specifiers
provided by `display-buffer-alist'.  If the value of the latter
is nil too, all specifiers are provided by the constant
`display-buffer-default-specifiers'.

As a special case, the `reuse-window' specifier allows to specify
as second element an arbitrary window, as third element an
arbitrary buffer, and as fourth element an arbitrary frame.  As
first element of a window/side pair of the `pop-up-window'
specifier you can specifiy an arbitrary window.

The optional third argument LABEL, if non-nil, must be a symbol
specifiying the buffer display label.  Applications should set
this when the buffer shall be displayed in some special way but
BUFFER-OR-NAME does not identify the buffer as special.  Typical
buffers that fit into this category are those whose names are
derived from the name of the file they are visiting.  A user can
override SPECIFIERS by adding an entry to `display-buffer-alist'
whose car contains LABEL and whose cdr specifies the preferred
alternative display method.

The method to display the buffer is derived by combining the
values of `display-buffer-alist' and SPECIFIERS.  Highest
priority is given to overriding elements of
`display-buffer-alist'.  Next come the elements specified by
SPECIFIERS, followed by the non-overriding elements of
`display-buffer-alist'.

The result must be a list of valid buffer display specifiers.  If
`display-buffer-function' is non-nil, call it with the buffer and
this list as arguments."
  (interactive "BDisplay buffer:\nP")
  (let* ((buffer (normalize-buffer-to-display buffer-or-name))
	 (buffer-name (buffer-name buffer))
	 (specifiers
	  ;; Normalize specifiers.
	  (display-buffer-normalize-specifiers buffer-name specifiers label))
	 ;; Don't use a minibuffer frame.
	 (frame (display-buffer-frame))
	 ;; `window' is the window we use for showing `buffer'.
	 window specifier method)
    ;; Reset this.
    (setq display-buffer-window nil)
    (if display-buffer-function
	;; Let `display-buffer-function' do the job.
	(funcall display-buffer-function buffer specifiers)
      ;; Retrieve the next location specifier while there a specifiers
      ;; left and we don't have a valid window.
      (while (and specifiers (not (window-live-p window)))
	(setq specifier (car specifiers))
	(setq specifiers (cdr specifiers))
	(setq method (car specifier))
	(setq window
	      (cond
	       ((eq method 'reuse-window)
		(display-buffer-reuse-window
		 buffer (cdr specifier) specifiers))
	       ((eq method 'pop-up-window)
		(display-buffer-pop-up-window
		 buffer (cdr specifier) specifiers))
	       ((eq method 'pop-up-frame)
		(display-buffer-pop-up-frame
		 buffer (cdr specifier) specifiers))
	       ((eq method 'use-side-window)
		(display-buffer-in-side-window
		 buffer (nth 1 specifier) (nth 2 specifier) specifiers))
	       ((eq method 'fun-with-args)
		(apply (cadr specifier) buffer (cddr specifier))))))

      ;; If we don't have a window yet, try a fallback method.  All
      ;; specifiers have been used up by now.
      (or (and (window-live-p window) window)
	  ;; Try reusing a window showing BUFFER on any visible or
	  ;; iconfied frame.
	  (display-buffer-reuse-window buffer '(nil buffer 0))
	  ;; Try reusing a window not showing BUFFER on any visible or
	  ;; iconified frame.
	  (display-buffer-reuse-window buffer '(nil other 0))
	  ;; Try making a new frame.
	  (display-buffer-pop-up-frame buffer)
	  ;; Try using a weakly dedicated window.
	  (display-buffer-reuse-window
	   buffer '(nil nil t) '((reuse-window-dedicated . weak)))
	  ;; Try using a strongly dedicated window.
	  (display-buffer-reuse-window
	   buffer '(nil nil t) '((reuse-window-dedicated . t)))))))

(defsubst display-buffer-same-window (&optional buffer-or-name label) 
  "Display buffer specified by BUFFER-OR-NAME in the selected window.
Another window will be used only if the buffer can't be shown in
the selected window, usually because it is dedicated to another
buffer.  Optional argument BUFFER-OR-NAME and LABEL are as for
`display-buffer'."
  (interactive "BDisplay buffer in same window:\nP")
  (display-buffer buffer-or-name 'same-window label))

(defsubst display-buffer-same-frame (&optional buffer-or-name label) 
  "Display buffer specified by BUFFER-OR-NAME in a window on the same frame.
Another frame will be used only if there is no other choice.
Optional argument BUFFER-OR-NAME and LABEL are as for
`display-buffer'."
  (interactive "BDisplay buffer on same frame:\nP")
  (display-buffer buffer-or-name 'same-frame label))

(defsubst display-buffer-other-window (&optional buffer-or-name label) 
  "Display buffer specified by BUFFER-OR-NAME in another window.
The selected window will be used only if there is no other
choice.  Windows on the selected frame are preferred to windows
on other frames.  Optional argument BUFFER-OR-NAME and LABEL are as
for `display-buffer'."
  (interactive "BDisplay buffer in another window:\nP")
  (display-buffer buffer-or-name 'other-window label))

(defun display-buffer-same-frame-other-window (&optional buffer-or-name label) 
  "Display buffer specified by BUFFER-OR-NAME in another window on the same frame.
The selected window or another frame will be used only if there
is no other choice.  Optional argument BUFFER-OR-NAME and LABEL are
as for `display-buffer'."
  (interactive "BDisplay buffer in another window on same frame:\nP")
  (display-buffer buffer-or-name 'same-frame-other-window label))

(defun display-buffer-other-frame (&optional buffer-or-name label)
  "Display buffer specified by BUFFER-OR-NAME on another frame.
The selected frame will be used only if there is no other choice.
Optional argument BUFFER-OR-NAME and LABEL are as for
`display-buffer'.

If this command uses another frame, it will also select that frame."
  (interactive "BDisplay buffer in other frame: ")
  (display-buffer buffer-or-name 'other-frame label))

(defun pop-to-buffer (&optional buffer-or-name specifiers norecord label)
  "Display buffer specified by BUFFER-OR-NAME and select the window used.
Optional argument BUFFER-OR-NAME may be a buffer, a string \(a
buffer name), or nil.  If BUFFER-OR-NAME is a string not naming
an existent buffer, create a buffer with that name.  If
BUFFER-OR-NAME is nil or omitted, display the current buffer.
Interactively, prompt for the buffer name using the minibuffer.

Optional second argument SPECIFIERS must be a list of buffer
display specifiers, a single location specifier, `t' which means
the latter means to display the buffer in any but the selected
window, or nil which means to exclusively apply the specifiers
customized by the user.

Optional argument NORECORD non-nil means do not put the buffer
specified by BUFFER-OR-NAME at the front of the buffer list and
do not make the window displaying it the most recently selected
one.

The optional argument LABEL, if non-nil, is a symbol specifying the
display purpose.  Applications should set this when the buffer
shall be displayed in a special way but BUFFER-OR-NAME does not
identify the buffer as special.  Buffers that typically fit into
this category are those whose names have been derived from the
name of the file they are visiting.

Return the buffer specified by BUFFER-OR-NAME or nil if
displaying the buffer failed.

This uses the function `display-buffer' as a subroutine; see the
documentations of `display-buffer' and `display-buffer-alist' for
additional information."
  (interactive "BPop to buffer:\nP")
  (let ((buffer (normalize-buffer-to-display buffer-or-name))
	(old-window (selected-window))
	(old-frame (selected-frame))
	new-window new-frame)
    (set-buffer buffer)
    (setq new-window (display-buffer buffer specifiers label))
    (unless (eq new-window old-window)
      ;; `display-buffer' has chosen another window, select it.
      (select-window new-window norecord)
      (setq new-frame (window-frame new-window))
      (unless (eq new-frame old-frame)
	;; `display-buffer' has chosen another frame, make sure it gets
	;; input focus and is risen.
	(select-frame-set-input-focus new-frame)))

    buffer))

(defsubst pop-to-buffer-same-window (&optional buffer-or-name norecord label)
  "Pop to buffer specified by BUFFER-OR-NAME in the selected window.
Another window will be used only if the buffer can't be shown in
the selected window, usually because it is dedicated to another
buffer.  Optional arguments BUFFER-OR-NAME, NORECORD and LABEL are
as for `pop-to-buffer'."
  (interactive "BPop to buffer in selected window:\nP")
  (pop-to-buffer buffer-or-name 'same-window norecord label))

(defsubst pop-to-buffer-same-frame (&optional buffer-or-name norecord label) 
  "Pop to buffer specified by BUFFER-OR-NAME in a window on the selected frame.
Another frame will be used only if there is no other choice.
Optional arguments BUFFER-OR-NAME, NORECORD and LABEL are as for
`pop-to-buffer'."
  (interactive "BPop to buffer on same frame:\nP")
  (pop-to-buffer buffer-or-name 'same-frame norecord label))

(defsubst pop-to-buffer-other-window (&optional buffer-or-name norecord label)
  "Pop to buffer specified by BUFFER-OR-NAME in another window.
The selected window will be used only if there is no other
choice.  Windows on the selected frame are preferred to windows
on other frames.  Optional arguments BUFFER-OR-NAME, NORECORD and
LABEL are as for `pop-to-buffer'."
  (interactive "BPop to buffer in another window:\nP")
  (pop-to-buffer buffer-or-name 'other-window norecord))

(defsubst pop-to-buffer-same-frame-other-window (&optional buffer-or-name norecord label) 
  "Pop to buffer specified by BUFFER-OR-NAME in another window on the selected frame.
The selected window or another frame will be used only if there
is no other choice.  Optional arguments BUFFER-OR-NAME, NORECORD
and LABEL are as for `pop-to-buffer'."
  (interactive "BPop to buffer in another window on same frame:\nP")
  (pop-to-buffer buffer-or-name 'same-frame-other-window norecord label))

(defsubst pop-to-buffer-other-frame (&optional buffer-or-name norecord label)
  "Pop to buffer specified by BUFFER-OR-NAME on another frame.
The selected frame will be used only if there's no other choice.
Optional arguments BUFFER-OR-NAME, NORECORD and LABEL are as for
`pop-to-buffer'."
  (interactive "BPop to buffer on another frame:\nP")
  (pop-to-buffer buffer-or-name 'other-frame norecord label))

(defun read-buffer-to-switch (prompt)
  "Read the name of a buffer to switch to, prompting with PROMPT.
Return the neame of the buffer as a string.

This function is intended for the `switch-to-buffer' family of
commands since these need to omit the name of the current buffer
from the list of completions and default values."
  (let ((rbts-completion-table (internal-complete-buffer-except)))
    (minibuffer-with-setup-hook
        (lambda ()
          (setq minibuffer-completion-table rbts-completion-table)
          ;; Since rbts-completion-table is built dynamically, we
          ;; can't just add it to the default value of
          ;; icomplete-with-completion-tables, so we add it
          ;; here manually.
          (if (and (boundp 'icomplete-with-completion-tables)
                   (listp icomplete-with-completion-tables))
              (set (make-local-variable 'icomplete-with-completion-tables)
                   (cons rbts-completion-table
                         icomplete-with-completion-tables))))
      (read-buffer prompt (other-buffer (current-buffer))
                   (confirm-nonexistent-file-or-buffer)))))

(defun normalize-buffer-to-switch-to (buffer-or-name)
  "Normalize BUFFER-OR-NAME argument of buffer switching functions.
If BUFFER-OR-NAME is nil, return the buffer returned by
`other-buffer'.  Else, if a buffer specified by BUFFER-OR-NAME
exists, return that buffer.  If no such buffer exists, create a
buffer with the name BUFFER-OR-NAME and return that buffer."
  (if buffer-or-name
      (or (get-buffer buffer-or-name)
	  (let ((buffer (get-buffer-create buffer-or-name)))
	    (set-buffer-major-mode buffer)
	    buffer))
    (other-buffer)))

(defun switch-to-buffer (buffer-or-name &optional norecord)
  "Switch to buffer BUFFER-OR-NAME in the selected window.
If called interactively, prompt for the buffer name using the
minibuffer.  The variable `confirm-nonexistent-file-or-buffer'
determines whether to request confirmation before creating a new
buffer.

BUFFER-OR-NAME may be a buffer, a string \(a buffer name), or
nil.  If BUFFER-OR-NAME is a string that does not identify an
existing buffer, create a buffer with that name.  If
BUFFER-OR-NAME is nil, switch to the buffer returned by
`other-buffer'.

Optional argument NORECORD non-nil means do not put the buffer
specified by BUFFER-OR-NAME at the front of the buffer list and
do not make the window displaying it the most recently selected
one.  Return the buffer switched to.

This function is intended for interactive use only.  Lisp
functions should call `pop-to-buffer-same-window' instead."
  (interactive
   (list (read-buffer-to-switch "Switch to buffer: ")))
  (let ((buffer (normalize-buffer-to-switch-to buffer-or-name)))
    (if (and (or (window-minibuffer-p) (eq (window-dedicated-p) t))
	     (not (eq buffer (window-buffer))))
	;; Cannot switch to another buffer in a minibuffer or strongly
	;; dedicated window that does not show the buffer already.  Call
	;; `pop-to-buffer' instead.
	(pop-to-buffer buffer 'same-window norecord)
      (unless (eq buffer (window-buffer))
	;; I'm not sure why we should NOT call `set-window-buffer' here,
	;; but let's keep things as they are (otherwise we could always
	;; call `pop-to-buffer-same-window' here).
	(set-window-buffer nil buffer))
      (unless norecord
	(select-window (selected-window)))
      (set-buffer buffer))))

(defun switch-to-buffer-same-frame (buffer-or-name &optional norecord)
  "Switch to buffer BUFFER-OR-NAME in a window on the selected frame.
Another frame will be used only if there is no other choice.
Arguments BUFFER-OR-NAME and NORECORD have the same meaning as
for `switch-to-buffer'.

This function is intended for interactive use only.  Lisp
functions should call `pop-to-buffer-same-frame' instead."
  (interactive
   (list (read-buffer-to-switch "Switch to buffer in other window: ")))
  (let ((buffer (normalize-buffer-to-switch-to buffer-or-name)))
    (pop-to-buffer buffer 'same-frame norecord)))

(defun switch-to-buffer-other-window (buffer-or-name &optional norecord)
  "Switch to buffer BUFFER-OR-NAME in another window.
The selected window will be used only if there is no other
choice.  Windows on the selected frame are preferred to windows
on other frames.  Arguments BUFFER-OR-NAME and NORECORD have the
same meaning as for `switch-to-buffer'.

This function is intended for interactive use only.  Lisp
functions should call `pop-to-buffer-other-window' instead."
  (interactive
   (list (read-buffer-to-switch "Switch to buffer in other window: ")))
  (let ((buffer (normalize-buffer-to-switch-to buffer-or-name)))
    (pop-to-buffer buffer 'other-window norecord)))

(defun switch-to-buffer-other-window-same-frame (buffer-or-name &optional norecord)
  "Switch to buffer BUFFER-OR-NAME in another window on the selected frame.
The selected window or another frame will be used only if there
is no other choice.  Arguments BUFFER-OR-NAME and NORECORD have
the same meaning as for `switch-to-buffer'.

This function is intended for interactive use only.  Lisp
functions should call `pop-to-buffer-other-window-same-frame'
instead."
  (interactive
   (list (read-buffer-to-switch "Switch to buffer in other window: ")))
  (let ((buffer (normalize-buffer-to-switch-to buffer-or-name)))
    (pop-to-buffer buffer 'same-frame-other-window norecord)))

(defun switch-to-buffer-other-frame (buffer-or-name &optional norecord)
  "Switch to buffer BUFFER-OR-NAME on another frame.
The same frame will be used only if there is no other choice.
Arguments BUFFER-OR-NAME and NORECORD have the same meaning
as for `switch-to-buffer'.

This function is intended for interactive use only.  Lisp
functions should call `pop-to-buffer-other-frame' instead."
  (interactive
   (list (read-buffer-to-switch "Switch to buffer in other frame: ")))
  (let ((buffer (normalize-buffer-to-switch-to buffer-or-name)))
    (pop-to-buffer buffer 'other-frame norecord)))

;;; Obsolete definitions of `display-buffer' below.
(defcustom same-window-buffer-names nil
  "List of names of buffers that should appear in the \"same\" window.
`display-buffer' and `pop-to-buffer' show a buffer whose name is
on this list in the selected rather than some other window.

An element of this list can be a cons cell instead of just a
string.  In that case, the cell's car must be a string specifying
the buffer name.  This is for compatibility with
`special-display-buffer-names'; the cdr of the cons cell is
ignored.

See also `same-window-regexps'."
 :type '(repeat (string :format "%v"))
 :group 'windows)
(make-obsolete-variable
 'same-window-buffer-names
 "use 2nd arg of `display-buffer' instead." "24.1")

(defcustom same-window-regexps nil
  "List of regexps saying which buffers should appear in the \"same\" window.
`display-buffer' and `pop-to-buffer' show a buffer whose name
matches a regexp on this list in the selected rather than some
other window.

An element of this list can be a cons cell instead of just a
string.  In that case, the cell's car must be a regexp matching
the buffer name.  This is for compatibility with
`special-display-regexps'; the cdr of the cons cell is ignored.

See also `same-window-buffer-names'."
  :type '(repeat (regexp :format "%v"))
  :group 'windows)
(make-obsolete-variable
 'same-window-regexps
 "use 2nd arg of `display-buffer' instead." "24.1")

(defun same-window-p (buffer-name)
  "Return non-nil if a buffer named BUFFER-NAME would be shown in the \"same\" window.
This function returns non-nil if `display-buffer' or
`pop-to-buffer' would show a buffer named BUFFER-NAME in the
selected rather than \(as usual\) some other window.  See
`same-window-buffer-names' and `same-window-regexps'."
  (let ((buffer-names (with-no-warnings same-window-buffer-names))
	(regexps (with-no-warnings same-window-regexps)))
    (cond
     ((not (stringp buffer-name)))
     ;; The elements of `same-window-buffer-names' can be buffer
     ;; names or cons cells whose cars are buffer names.
     ((member buffer-name buffer-names))
     ((assoc buffer-name buffer-names))
     ((catch 'found
	(dolist (regexp regexps)
	  ;; The elements of `same-window-regexps' can be regexps
	  ;; or cons cells whose cars are regexps.
	  (when (or (and (stringp regexp)
			 (string-match regexp buffer-name))
		    (and (consp regexp) (stringp (car regexp))
			 (string-match-p (car regexp) buffer-name)))
	    (throw 'found t))))))))
(make-obsolete
 'same-window-p "pass argument to buffer display function instead." "24.1")

(defcustom special-display-frame-alist
  '((height . 14) (width . 80) (unsplittable . t))
  "Alist of parameters for special frames.
Special frames are used for buffers whose names are listed in
`special-display-buffer-names' and for buffers whose names match
one of the regular expressions in `special-display-regexps'.

This variable can be set in your init file, like this:

  (setq special-display-frame-alist '((width . 80) (height . 20)))

These supersede the values given in `default-frame-alist'."
  :type '(repeat (cons :format "%v"
			 (symbol :tag "Parameter")
			 (sexp :tag "Value")))
  :group 'frames)
(make-obsolete-variable
 'special-display-frame-alist
 "use 2nd arg of `display-buffer' instead." "24.1")

(defun special-display-popup-frame (buffer &optional args)
  "Display BUFFER in a special frame and return the window chosen.
If BUFFER is already displayed in a visible or iconified frame,
raise that frame.  Otherwise, display BUFFER in a way as
specified by optional argument ARGS.

If ARGS is an alist, use it as a list of frame parameters.  If
these parameters contain \(same-window . t), display BUFFER in
the selected window.  If they contain \(same-frame . t), display
BUFFER in a window on the selected frame.

If ARGS is a list whose car is a symbol, use (car ARGS) as a
function to do the work.  Pass it BUFFER as first argument,
and (cdr ARGS) as second."
  (if (and args (symbolp (car args)))
      (apply (car args) buffer (cdr args))
    (let ((window (get-buffer-window buffer 0)))
      (or
       ;; If we have a window already, make it visible.
       (when window
	 (let ((frame (window-frame window)))
	   (make-frame-visible frame)
	   (raise-frame frame)
	   window))
       ;; Reuse the current window if the user requested it.
       (when (cdr (assq 'same-window args))
	 (display-buffer-reuse-window
	  buffer '(same nil nil) '((reuse-dedicated . weak))))
       ;; Stay on the same frame if requested.
       (when (or (cdr (assq 'same-frame args))
		 (cdr (assq 'same-window args)))
	 (or (display-buffer-pop-up-window
	      buffer '((largest . nil) (lru . nil)))
	     (display-buffer-reuse-window
	      buffer '(nil nil nil))))
       ;; If no window yet, make one in a new frame.
       (let ((frame
	      (with-current-buffer buffer
		(make-frame
		 (append args (with-no-warnings
				special-display-frame-alist))))))
	 (set-window-buffer (frame-selected-window frame) buffer)
	 (set-window-dedicated-p (frame-selected-window frame) t)
	 (frame-selected-window frame))))))
(make-obsolete
 'special-display-popup-frame
 "use 2nd arg of `display-buffer' instead." "24.1")

(defcustom special-display-function 'special-display-popup-frame
  "Function to call for displaying special buffers.
This function is called with two arguments - the buffer and,
optionally, a list - and should return a window displaying that
buffer.  The default value usually makes a separate frame for the
buffer using `special-display-frame-alist' to specify the frame
parameters.  See the definition of `special-display-popup-frame'
for how to specify such a function.

A buffer is special when its name is either listed in
`special-display-buffer-names' or matches a regexp in
`special-display-regexps'."
  :type 'function
  :group 'windows
  :group 'frames)
(make-obsolete-variable
 'special-display-function
 "use 2nd arg of `display-buffer' instead." "24.1")

(defcustom special-display-buffer-names nil
  "List of names of buffers that should be displayed specially.
Displaying a buffer with `display-buffer' or `pop-to-buffer', if
its name is in this list, displays the buffer in a way specified
by `special-display-function'.  `special-display-popup-frame'
\(the default for `special-display-function') usually displays
the buffer in a separate frame made with the parameters specified
by `special-display-frame-alist'.  If `special-display-function'
has been set to some other function, that function is called with
the buffer as first, and nil as second argument.

Alternatively, an element of this list can be specified as
\(BUFFER-NAME FRAME-PARAMETERS), where BUFFER-NAME is a buffer
name and FRAME-PARAMETERS an alist of \(PARAMETER . VALUE) pairs.
`special-display-popup-frame' will interpret such pairs as frame
parameters when it creates a special frame, overriding the
corresponding values from `special-display-frame-alist'.

As a special case, if FRAME-PARAMETERS contains (same-window . t)
`special-display-popup-frame' displays that buffer in the
selected window.  If FRAME-PARAMETERS contains (same-frame . t),
it displays that buffer in a window on the selected frame.

If `special-display-function' specifies some other function than
`special-display-popup-frame', that function is called with the
buffer named BUFFER-NAME as first, and FRAME-PARAMETERS as second
argument.

Finally, an element of this list can be also specified as
\(BUFFER-NAME FUNCTION OTHER-ARGS).  In that case,
`special-display-popup-frame' will call FUNCTION with the buffer
named BUFFER-NAME as first argument, and OTHER-ARGS as the
second.  If `special-display-function' specifies some other
function, that function is called with the buffer named
BUFFER-NAME as first, and the element's cdr as second argument.

If this variable appears \"not to work\", because you added a
name to it but the corresponding buffer is displayed in the
selected window, look at the values of `same-window-buffer-names'
and `same-window-regexps'.  Those variables take precedence over
this one.

See also `special-display-regexps'."
  :type '(repeat
	  (choice :tag "Buffer"
		  :value ""
		  (string :format "%v")
		  (cons :tag "With parameters"
			:format "%v"
			:value ("" . nil)
			(string :format "%v")
			(repeat :tag "Parameters"
				(cons :format "%v"
				      (symbol :tag "Parameter")
				      (sexp :tag "Value"))))
		  (list :tag "With function"
			:format "%v"
			:value ("" . nil)
			(string :format "%v")
			(function :tag "Function")
			(repeat :tag "Arguments" (sexp)))))
  :group 'windows
  :group 'frames)
(make-obsolete-variable
 'special-display-buffer-names
 "use 2nd arg of `display-buffer' instead." "24.1")

;;;###autoload
(put 'special-display-buffer-names 'risky-local-variable t)

(defcustom special-display-regexps nil
  "List of regexps saying which buffers should be displayed specially.
Displaying a buffer with `display-buffer' or `pop-to-buffer', if
any regexp in this list matches its name, displays it specially
using `special-display-function'.  `special-display-popup-frame'
\(the default for `special-display-function') usually displays
the buffer in a separate frame made with the parameters specified
by `special-display-frame-alist'.  If `special-display-function'
has been set to some other function, that function is called with
the buffer as first, and nil as second argument.

Alternatively, an element of this list can be specified as
\(REGEXP FRAME-PARAMETERS), where REGEXP is a regexp as above and
FRAME-PARAMETERS an alist of (PARAMETER . VALUE) pairs.
`special-display-popup-frame' will then interpret these pairs as
frame parameters when creating a special frame for a buffer whose
name matches REGEXP, overriding the corresponding values from
`special-display-frame-alist'.

As a special case, if FRAME-PARAMETERS contains (same-window . t)
`special-display-popup-frame' displays buffers matching REGEXP in
the selected window.  \(same-frame . t) in FRAME-PARAMETERS means
to display such buffers in a window on the selected frame.

If `special-display-function' specifies some other function than
`special-display-popup-frame', that function is called with the
buffer whose name matched REGEXP as first, and FRAME-PARAMETERS
as second argument.

Finally, an element of this list can be also specified as
\(REGEXP FUNCTION OTHER-ARGS).  `special-display-popup-frame'
will then call FUNCTION with the buffer whose name matched
REGEXP as first, and OTHER-ARGS as second argument.  If
`special-display-function' specifies some other function, that
function is called with the buffer whose name matched REGEXP
as first, and the element's cdr as second argument.

If this variable appears \"not to work\", because you added a
name to it but the corresponding buffer is displayed in the
selected window, look at the values of `same-window-buffer-names'
and `same-window-regexps'.  Those variables take precedence over
this one.

See also `special-display-buffer-names'."
  :type '(repeat
	  (choice :tag "Buffer"
		  :value ""
		  (regexp :format "%v")
		  (cons :tag "With parameters"
			:format "%v"
			:value ("" . nil)
			(regexp :format "%v")
			(repeat :tag "Parameters"
				(cons :format "%v"
				      (symbol :tag "Parameter")
				      (sexp :tag "Value"))))
		  (list :tag "With function"
			:format "%v"
			:value ("" . nil)
			(regexp :format "%v")
			(function :tag "Function")
			(repeat :tag "Arguments" (sexp)))))
  :group 'windows
  :group 'frames)
(make-obsolete-variable
 'special-display-regexps
 "use 2nd arg of `display-buffer' instead." "24.1")

(defun special-display-p (buffer-name)
  "Return non-nil if a buffer named BUFFER-NAME gets a special frame.
More precisely, return t if `special-display-buffer-names' or
`special-display-regexps' contain a string entry equaling or
matching BUFFER-NAME.  If `special-display-buffer-names' or
`special-display-regexps' contain a list entry whose car equals
or matches BUFFER-NAME, the return value is the cdr of that
entry."
  (let ((buffer-names (with-no-warnings special-display-buffer-names))
	(regexps (with-no-warnings special-display-regexps))
	tmp)
    (cond
     ((not (stringp buffer-name)))
     ((member buffer-name buffer-names)
      t)
     ((setq tmp (assoc buffer-name buffer-names))
      (cdr tmp))
     ((catch 'found
	(dolist (regexp regexps)
	  (cond
	   ((stringp regexp)
	    (when (string-match-p regexp buffer-name)
	      (throw 'found t)))
	   ((and (consp regexp) (stringp (car regexp))
		 (string-match-p (car regexp) buffer-name))
	    (throw 'found (cdr regexp))))))))))
(make-obsolete
 'special-display-p
 "pass argument to buffer display function instead." "24.1")

(defcustom pop-up-frame-alist nil
  "Alist of parameters for automatically generated new frames.
You can set this in your init file; for example,

  (setq pop-up-frame-alist '((width . 80) (height . 20)))

If non-nil, the value you specify here is used by the default
`pop-up-frame-function' for the creation of new frames.

Since `pop-up-frame-function' is used by `display-buffer' for
making new frames, any value specified here by default affects
the automatic generation of new frames via `display-buffer' and
all functions based on it.  The behavior of `make-frame' is not
affected by this variable."
  :type '(repeat (cons :format "%v"
		       (symbol :tag "Parameter")
		       (sexp :tag "Value")))
  :group 'frames)
(make-obsolete-variable
 'pop-up-frame-alist
 "use 2nd arg of `display-buffer' instead." "24.1")

(defcustom pop-up-frame-function
  (lambda () (make-frame pop-up-frame-alist))
  "Function used by `display-buffer' for creating a new frame.
This function is called with no arguments and should return a new
frame.  The default value calls `make-frame' with the argument
`pop-up-frame-alist'."
  :type 'function
  :group 'frames)
(make-obsolete-variable
 'pop-up-frame-function
 "use 2nd arg of `display-buffer' instead." "24.1")

(defcustom pop-up-frames nil
  "Whether `display-buffer' should make a separate frame.
If nil, never make a separate frame.
If the value is `graphic-only', make a separate frame
on graphic displays only.
Any other non-nil value means always make a separate frame."
  :type '(choice
	  (const :tag "Never" nil)
	  (const :tag "On graphic displays only" graphic-only)
	  (const :tag "Always" t))
  :group 'windows
  :group 'frames)
(make-obsolete-variable
 'pop-up-frames
 "use 2nd arg of `display-buffer' instead." "24.1")

(defcustom display-buffer-reuse-frames nil
  "Set and non-nil means `display-buffer' should reuse frames.
If the buffer in question is already displayed in a frame, raise
that frame."
  :type 'boolean
  :version "21.1"
  :group 'windows
  :group 'frames)
(make-obsolete-variable
 'display-buffer-reuse-frames
 "use 2nd arg of `display-buffer' instead." "24.1")

(defcustom pop-up-windows 'unset ; t
  "Set and non-nil means `display-buffer' should make a new window."
  :type 'boolean
  :version "24.1"
  :group 'windows)
(make-obsolete-variable
 'pop-up-windows
 "use 2nd arg of `display-buffer' instead." "24.1")

(defcustom split-window-preferred-function 'split-window-sensibly
  "Function called by `display-buffer' to split a window.
This function is called with a window as single argument and is
supposed to split that window and return the new window.  If the
window can (or shall) not be split, it is supposed to return nil.

The default is to call the function `split-window-sensibly' which
tries to split the window in a way which seems most suitable.
You can customize the options `split-height-threshold' and/or
`split-width-threshold' in order to have `split-window-sensibly'
prefer either vertical or horizontal splitting.

If you set this to any other function, bear in mind that
`display-buffer' may call that function repeatedly; the option
`pop-up-windows' controls which windows may become the argument
of this function.

The window selected at the time `display-buffer' was invoked is
still selected when this function is called.  Hence you can
compare the window argument with the value of `selected-window'
if you intend to split the selected window instead or if you do
not want to split the selected window."
  :type 'function
  :version "23.1"
  :group 'windows)
(make-obsolete-variable
 'split-window-preferred-function
 "use 2nd arg of `display-buffer' instead." "24.1")

(defcustom split-height-threshold 80
  "Minimum height for splitting a window to display a buffer.
If this is an integer, `display-buffer' can split a window
vertically only if it has at least this many lines.  If this is
nil, `display-buffer' does not split windows vertically.  If a
window is the only window on its frame, `display-buffer' may
split it vertically disregarding the value of this variable."
  :type '(choice (const nil) (integer :tag "lines"))
  :version "23.1"
  :group 'windows)
(make-obsolete-variable
 'split-height-threshold
 "use 2nd arg of `display-buffer' instead." "24.1")

(defcustom split-width-threshold 160
  "Minimum width for splitting a window to display a buffer.
If this is an integer, `display-buffer' can split a window
horizontally only if it has at least this many columns.  If this
is nil, `display-buffer' cannot split windows horizontally."
  :type '(choice (const nil) (integer :tag "columns"))
  :version "23.1"
  :group 'windows)
(make-obsolete-variable
 'split-width-threshold
 "use 2nd arg of `display-buffer' instead." "24.1")

(defcustom even-window-heights 'unset ; t
  "If set and non-nil `display-buffer' will try to even window heights.
Otherwise `display-buffer' will leave the window configuration
alone.  Heights are evened only when `display-buffer' reuses a
window that appears above or below the selected window."
  :type 'boolean
  :version "24.1"
  :group 'windows)
(make-obsolete-variable
 'even-window-heights
 "use 2nd arg of `display-buffer' instead." "24.1")

(defvar display-buffer-mark-dedicated nil
  "Non-nil means `display-buffer' marks the windows it creates as dedicated.
The actual non-nil value of this variable will be copied to the
`window-dedicated-p' flag.")
(make-obsolete-variable
 'display-buffer-mark-dedicated
 "use 2nd arg of `display-buffer' instead." "24.1")

(defun window-splittable-p (window &optional horizontal)
  "Return non-nil if `split-window-sensibly' may split WINDOW.
Optional argument HORIZONTAL nil or omitted means check whether
`split-window-sensibly' may split WINDOW vertically.  HORIZONTAL
non-nil means check whether WINDOW may be split horizontally.

WINDOW may be split vertically when the following conditions
hold:
- `window-size-fixed' is either nil or equals `width' for the
  buffer of WINDOW.
- `split-height-threshold' is an integer and WINDOW is at least as
  high as `split-height-threshold'.
- When WINDOW is split evenly, the emanating windows are at least
  `window-min-height' lines tall and can accommodate at least one
  line plus - if WINDOW has one - a mode line.

WINDOW may be split horizontally when the following conditions
hold:
- `window-size-fixed' is either nil or equals `height' for the
  buffer of WINDOW.
- `split-width-threshold' is an integer and WINDOW is at least as
  wide as `split-width-threshold'.
- When WINDOW is split evenly, the emanating windows are at least
  `window-min-width' or two (whichever is larger) columns wide."
  (when (window-live-p window)
    (with-current-buffer (window-buffer window)
      (if horizontal
	  ;; A window can be split horizontally when its width is not
	  ;; fixed, it is at least `split-width-threshold' columns wide
	  ;; and at least twice as wide as `window-min-width' and 2 (the
	  ;; latter value is hardcoded).
	  (and (memq window-size-fixed '(nil height))
	       ;; Testing `window-full-width-p' here hardly makes any
	       ;; sense nowadays.  This can be done more intuitively by
	       ;; setting up `split-width-threshold' appropriately.
	       (numberp split-width-threshold)
	       (>= (window-width window)
		   (max split-width-threshold
			(* 2 (max window-min-width 2)))))
	;; A window can be split vertically when its height is not
	;; fixed, it is at least `split-height-threshold' lines high,
	;; and it is at least twice as high as `window-min-height' and 2
	;; if it has a modeline or 1.
	(and (memq window-size-fixed '(nil width))
	     (numberp split-height-threshold)
	     (>= (window-height window)
		 (max split-height-threshold
		      (* 2 (max window-min-height
				(if mode-line-format 2 1))))))))))
(make-obsolete
 'window-splittable-p "use 2nd arg of `display-buffer' instead." "24.1")

(defun split-window-sensibly (window)
  "Split WINDOW in a way suitable for `display-buffer'.
If `split-height-threshold' specifies an integer, WINDOW is at
least `split-height-threshold' lines tall and can be split
vertically, split WINDOW into two windows one above the other and
return the lower window.  Otherwise, if `split-width-threshold'
specifies an integer, WINDOW is at least `split-width-threshold'
columns wide and can be split horizontally, split WINDOW into two
windows side by side and return the window on the right.  If this
can't be done either and WINDOW is the only window on its frame,
try to split WINDOW vertically disregarding any value specified
by `split-height-threshold'.  If that succeeds, return the lower
window.  Return nil otherwise.

By default `display-buffer' routines call this function to split
the largest or least recently used window.  To change the default
customize the option `split-window-preferred-function'.

You can enforce this function to not split WINDOW horizontally,
by setting \(or binding) the variable `split-width-threshold' to
nil.  If, in addition, you set `split-height-threshold' to zero,
chances increase that this function does split WINDOW vertically.

In order to not split WINDOW vertically, set \(or bind) the
variable `split-height-threshold' to nil.  Additionally, you can
set `split-width-threshold' to zero to make a horizontal split
more likely to occur.

Have a look at the function `window-splittable-p' if you want to
know how `split-window-sensibly' determines whether WINDOW can be
split."
  (or (and (with-no-warnings (window-splittable-p window))
	   ;; Split window vertically.
	   (with-selected-window window
	     (split-window-vertically)))
      (and (with-no-warnings (window-splittable-p window t))
	   ;; Split window horizontally.
	   (with-selected-window window
	     (split-window-horizontally)))
      (and (eq window (frame-root-window (window-frame window)))
	   (not (window-minibuffer-p window))
	   ;; If WINDOW is the only window on its frame and is not the
	   ;; minibuffer window, try to split it vertically disregarding
	   ;; the value of `split-height-threshold'.
	   (let ((split-height-threshold 0))
	     (when (with-no-warnings (window-splittable-p window))
	       (with-selected-window window
		 (split-window-vertically)))))))
(make-obsolete
 'split-window-sensibly "use 2nd arg of `display-buffer' instead." "24.1")

;; Functions for converting Emacs 23 buffer display options to buffer
;; display specifiers.
(defun display-buffer-alist-add (identifiers specifiers &optional no-custom)
  "Helper function for `display-buffer-alist-set'."
  (unless identifiers
    (setq identifiers '((regexp . ".*"))))
  (unless (atom specifiers)
    (setq specifiers (delq nil specifiers)))

  (if no-custom
      (setq display-buffer-alist
	    (cons (cons identifiers specifiers) display-buffer-alist))
    (customize-set-variable
     'display-buffer-alist
     (cons (cons identifiers specifiers) display-buffer-alist))))

(defun display-buffer-alist-set (&optional no-custom add)
  "Set `display-buffer-alist' from Emacs 23 buffer display options.
Optional argument NO-CUSTOM nil means use `customize-set-variable'
to set the value of `display-buffer-alist'.  NO-CUSTOM non-nil
means to use `setq' instead.

Optional argument ADD nil means to replace the actual value of
`display-buffer-alist' with the value calculated here.  ADD
non-nil means prepend the value calculated here to the current
value of `display-buffer-alist'."
  (unless add
    (if no-custom
	(setq display-buffer-alist nil)
      (customize-set-variable 'display-buffer-alist nil)))

  ;; Disable warnings, there are too many obsolete options here.
  (with-no-warnings
    ;; `pop-up-windows'
    (display-buffer-alist-add
     nil
     (let ((fun (unless (eq split-window-preferred-function
			    'split-window-sensibly)
		  ;; `split-window-sensibly' has been merged into the
		  ;; `display-buffer-split-window' code as `nil'.
		  split-window-preferred-function))
	   (min-height
	    (if (numberp split-height-threshold)
		(/ split-height-threshold 2)
	      ;; Undocumented hack.
	      1.0))
	   (min-width
	    (if (numberp split-width-threshold)
		(/ split-width-threshold 2)
	      ;; Undocumented hack.
	      1.0)))
       (list
	'pop-up-window
	(when pop-up-windows ; unset qualifies as t
	  (list
	   'pop-up-window
	   (cons 'largest fun)
	   (cons 'lru fun)))
	(cons 'pop-up-window-min-height min-height)
	(cons 'pop-up-window-min-width min-width)))
     no-custom)

    ;; `pop-up-frames'
    (display-buffer-alist-add
     nil
     (list
      'pop-up-frame
      (when pop-up-frames
	(list 'pop-up-frame pop-up-frames))
      (when pop-up-frame-function
	(cons 'pop-up-frame-function pop-up-frame-function))
      (when pop-up-frame-alist
	(cons 'pop-up-frame-alist pop-up-frame-alist)))
     no-custom)

    ;; `special-display-regexps'
    (dolist (entry special-display-regexps)
      (cond
       ((stringp entry)
	;; Plain string.
	(display-buffer-alist-add
	 `((regexp . ,entry))
	 (list
	  'fun-with-args
	  (list 'fun-with-args special-display-function
		special-display-frame-alist))
	 no-custom))
       ((consp entry)
	(let ((name (car entry))
	      (rest (cdr entry)))
	  (cond
	   ((functionp (car rest))
	    ;; A function.
	    (display-buffer-alist-add
	     `((name . ,name))
	     (list
	      'fun-with-args
	      ;; Weary.
	      (list 'fun-with-args (car rest) (cadr rest)))
	     no-custom))
	   ((listp rest)
	    ;; A list of parameters.
	    (cond
	     ((assq 'same-window rest)
	      (display-buffer-alist-add
	       `((name . ,name))
	       (list 'reuse-window
		     (list 'reuse-window 'same)
		     (list 'reuse-window-dedicated 'weak))
	       no-custom))
	     ((assq 'same-frame rest)
	      (display-buffer-alist-add
	       `((name . ,name)) (list 'same-frame) no-custom))
	     (t
	      (display-buffer-alist-add
	       `((name . ,name))
	       (list
		'fun-with-args
		(list 'fun-with-args special-display-function
		      special-display-frame-alist))
	       no-custom)))))))))

    ;; `special-display-buffer-names'
    (dolist (entry special-display-buffer-names)
      (cond
       ((stringp entry)
	;; Plain string.
	(display-buffer-alist-add
	 `((name . ,entry))
	 (list
	  'fun-with-args
	  (list 'fun-with-args special-display-function
		special-display-frame-alist))
	 no-custom))
       ((consp entry)
	(let ((name (car entry))
	      (rest (cdr entry)))
	  (cond
	   ((functionp (car rest))
	    ;; A function.
	    (display-buffer-alist-add
	     `((name . ,name))
	     (list
	      'fun-with-args
	      ;; Weary.
	      (list 'fun-with-args (car rest) (cadr rest)))
	     no-custom))
	   ((listp rest)
	    ;; A list of parameters.
	    (cond
	     ((assq 'same-window rest)
	      (display-buffer-alist-add
	       `((name . ,name))
	       (list 'reuse-window
		     (list 'reuse-window 'same)
		     (list 'reuse-window-dedicated 'weak))
	       no-custom))
	     ((assq 'same-frame rest)
	      (display-buffer-alist-add
	       `((name . ,name)) (list 'same-frame) no-custom))
	     (t
	      (display-buffer-alist-add
	       `((name . ,name))
	       (list
		'fun-with-args
		(list 'fun-with-args special-display-function
		      special-display-frame-alist))
	       no-custom)))))))))

    ;; `same-window-regexps'
    (dolist (entry same-window-regexps)
      (cond
       ((stringp entry)
	(display-buffer-alist-add
	 `((regexp . ,entry))
	 (list 'reuse-window (list 'reuse-window 'same))
	 no-custom))
       ((consp entry)
	(display-buffer-alist-add
	 `((regexp . ,(car entry)))
	 (list 'reuse-window (list 'reuse-window 'same))
	 no-custom))))

    ;; `same-window-buffer-names'
    (dolist (entry same-window-buffer-names)
      (cond
       ((stringp entry)
	(display-buffer-alist-add
	 `((name . ,entry))
	 (list 'reuse-window (list 'reuse-window 'same))
	 no-custom))
       ((consp entry)
	(display-buffer-alist-add
	 `((name . ,(car entry)))
	 (list 'reuse-window (list 'reuse-window 'same))
	 no-custom))))

    ;; `reuse-window'
    (display-buffer-alist-add
     nil
     (list
      'reuse-window
      (list 'reuse-window nil 'same
	    (when (or display-buffer-reuse-frames pop-up-frames)
	      ;; "0" (all visible and iconified frames) is hardcoded in
	      ;; Emacs 23.
		0))
      (unless (memq even-window-heights '(nil unset))
	(cons 'reuse-window-even-sizes t)))
     no-custom)

    ;; `display-buffer-mark-dedicated'
    (when display-buffer-mark-dedicated
      (display-buffer-alist-add
       nil
       (list
	(cons 'dedicated display-buffer-mark-dedicated))
       no-custom)))

  display-buffer-alist)

(defun set-window-text-height (window height)
  "Set the height in lines of the text display area of WINDOW to HEIGHT.
WINDOW must be a live window.  HEIGHT doesn't include the mode
line or header line, if any, or any partial-height lines in the
text display area.

Note that the current implementation of this function cannot
always set the height exactly, but attempts to be conservative,
by allocating more lines than are actually needed in the case
where some error may be present."
  (setq window (normalize-live-window window))
  (let ((delta (- height (window-text-height window))))
    (unless (zerop delta)
      ;; Setting window-min-height to a value like 1 can lead to very
      ;; bizarre displays because it also allows Emacs to make *other*
      ;; windows 1-line tall, which means that there's no more space for
      ;; the modeline.
      (let ((window-min-height (min 2 height))) ; One text line plus a modeline.
	(resize-window window delta)))))

(defun enlarge-window-horizontally (delta)
  "Make selected window DELTA columns wider.
Interactively, if no argument is given, make selected window one
column wider."
  (interactive "p")
  (enlarge-window delta t))

(defun shrink-window-horizontally (delta)
  "Make selected window DELTA columns narrower.
Interactively, if no argument is given, make selected window one
column narrower."
  (interactive "p")
  (shrink-window delta t))

(defun count-screen-lines (&optional beg end count-final-newline window)
  "Return the number of screen lines in the region.
The number of screen lines may be different from the number of actual lines,
due to line breaking, display table, etc.

Optional arguments BEG and END default to `point-min' and `point-max'
respectively.

If region ends with a newline, ignore it unless optional third argument
COUNT-FINAL-NEWLINE is non-nil.

The optional fourth argument WINDOW specifies the window used for obtaining
parameters such as width, horizontal scrolling, and so on.  The default is
to use the selected window's parameters.

Like `vertical-motion', `count-screen-lines' always uses the current buffer,
regardless of which buffer is displayed in WINDOW.  This makes possible to use
`count-screen-lines' in any buffer, whether or not it is currently displayed
in some window."
  (unless beg
    (setq beg (point-min)))
  (unless end
    (setq end (point-max)))
  (if (= beg end)
      0
    (save-excursion
      (save-restriction
        (widen)
        (narrow-to-region (min beg end)
                          (if (and (not count-final-newline)
                                   (= ?\n (char-before (max beg end))))
                              (1- (max beg end))
                            (max beg end)))
        (goto-char (point-min))
        (1+ (vertical-motion (buffer-size) window))))))

(defun window-buffer-height (window)
  "Return the height (in screen lines) of the buffer that WINDOW is displaying."
  (with-current-buffer (window-buffer window)
    (max 1
	 (count-screen-lines (point-min) (point-max)
			     ;; If buffer ends with a newline, ignore it when
			     ;; counting height unless point is after it.
			     (eobp)
			     window))))

;;; Resizing buffers to fit their contents exactly.
(defun fit-window-to-buffer (&optional window max-height min-height override)
  "Adjust height of WINDOW to display its buffer's contents exactly.
WINDOW can be any live window and defaults to the selected one.

Optional argument MAX-HEIGHT specifies the maximum height of
WINDOW and defaults to the height of WINDOW's frame.  Optional
argument MIN-HEIGHT specifies the minimum height of WINDOW and
defaults to `window-min-height'.  Both, MAX-HEIGHT and MIN-HEIGHT
are specified in lines and include the mode line and header line,
if any.

Optional argument OVERRIDE non-nil means override restrictions
imposed by `window-min-height' and `window-min-width' on the size
of WINDOW.

Return the number of lines by which WINDOW was enlarged or
shrunk.  If an error occurs during resizing, return nil but don't
signal an error.

Note that even if this function makes WINDOW large enough to show
_all_ lines of its buffer you might not see the first lines when
WINDOW was scrolled."
  (interactive)
  ;; Do all the work in WINDOW and its buffer and restore the selected
  ;; window and the current buffer when we're done.
  (setq window (normalize-live-window window))
  ;; Can't resize a full height or fixed-size window.
  (unless (or (window-size-fixed-p window) 
	      (window-full-height-p window))
    ;; `with-selected-window' should orderly restore the current buffer.
    (with-selected-window window
      ;; We are in WINDOW's buffer now.
      (let* ( ;; Adjust MIN-HEIGHT.
	     (min-height
	      (if override
		  (window-min-size window nil window)
		(max (or min-height window-min-height)
		     window-safe-min-height)))
	     (max-window-height
	      (window-total-size (frame-root-window window)))
	     ;; Adjust MAX-HEIGHT.
	     (max-height
	      (if (or override (not max-height))
		  max-window-height
		(min max-height max-window-height)))
	     ;; Make `desired-height' the height necessary to show
	     ;; all of WINDOW's buffer, constrained by MIN-HEIGHT
	     ;; and MAX-HEIGHT.
	     (desired-height
	      (max
	       (min
		(+ (count-screen-lines)
		   ;; For non-minibuffers count the mode line, if any.
		   (if (and (not (window-minibuffer-p window))
			    mode-line-format)
		       1
		     0)
		   ;; Count the header line, if any.
		   (if header-line-format 1 0))
		max-height)
	       min-height))
	     (desired-delta
	      (- desired-height (window-total-size window)))
	     (delta
	      (if (> desired-delta 0)
		  (min desired-delta
		       (window-max-delta window nil window))
		(max desired-delta
		     (- (window-min-delta window nil window))))))
	;; This `condition-case' shouldn't be necessary, but who knows?
	(condition-case nil
	    (if (zerop delta)
		;; Return zero if DELTA became zero in the proces.
		0
	      ;; Don't try to redisplay with the cursor at the end on its
	      ;; own line--that would force a scroll and spoil things.
	      (when (and (eobp) (bolp) (not (bobp)))
		;; It's silly to put `point' at the end of the previous
		;; line and so maybe force horizontal scrolling.
		(set-window-point window (line-beginning-position 0)))
	      ;; Call `resize-window' with OVERRIDE argument equal WINDOW.
	      (resize-window window delta nil window)
	      ;; Check if the last line is surely fully visible.  If
	      ;; not, enlarge the window.
	      (let ((end (save-excursion
			   (goto-char (point-max))
			   (when (and (bolp) (not (bobp)))
			     ;; Don't include final newline.
			     (backward-char 1))
			   (when truncate-lines
			     ;; If line-wrapping is turned off, test the
			     ;; beginning of the last line for
			     ;; visibility instead of the end, as the
			     ;; end of the line could be invisible by
			     ;; virtue of extending past the edge of the
			     ;; window.
			     (forward-line 0))
			   (point))))
		(set-window-vscroll window 0)
		;; This loop might in some rare pathological cases raise
		;; an error - another reason for the `condition-case'.
		(while (and (< desired-height max-height)
			    (= desired-height (window-total-size))
			    (not (pos-visible-in-window-p end)))
		  (resize-window window 1 nil window)
		  (setq desired-height (1+ desired-height)))))
	  (error (setq delta nil)))
	delta))))

(defun window-safely-shrinkable-p (&optional window)
  "Return t if WINDOW can be shrunk without shrinking other windows.
WINDOW defaults to the selected window."
  (with-selected-window (or window (selected-window))
    (let ((edges (window-edges)))
      ;; The following doesn't satisfy the doc-string's claim when
      ;; window and previous-/next-window are not part of the same
      ;; combination but still share a common edge.  Using
      ;; `window-iso-combined-p' instead should handle that.
      (or (= (nth 2 edges) (nth 2 (window-edges (previous-window))))
	  (= (nth 0 edges) (nth 0 (window-edges (next-window))))))))
(make-obsolete
 'window-safely-shrinkable-p "use `window-iso-combined-p' instead." "24.1")

(defun shrink-window-if-larger-than-buffer (&optional window)
  "Shrink height of WINDOW if its buffer doesn't need so many lines.
More precisely, shrink WINDOW vertically to be as small as
possible, while still showing the full contents of its buffer.
WINDOW defaults to the selected window.

Do not shrink WINDOW to less than `window-min-height' lines.  Do
nothing if the buffer contains more lines than the present window
height, or if some of the window's contents are scrolled out of
view, or if shrinking this window would also shrink another
window, or if the window is the only window of its frame.

Return non-nil if the window was shrunk, nil otherwise."
  (interactive)
  (setq window (normalize-live-window window))
  ;; Make sure that WINDOW is vertically combined and `point-min' is
  ;; visible (for whatever reason that's needed).  The remaining issues
  ;; should be taken care of by `fit-window-to-buffer'.
  (when (and (window-iso-combined-p window)
	     (pos-visible-in-window-p (point-min) window))
    (fit-window-to-buffer window (window-total-size window))))

(defun kill-buffer-and-window ()
  "Kill the current buffer and delete the selected window."
  (interactive)
  (let ((window-to-delete (selected-window))
	(buffer-to-kill (current-buffer))
	(delete-window-hook (lambda () (ignore-errors (delete-window)))))
    (unwind-protect
	(progn
	  (add-hook 'kill-buffer-hook delete-window-hook t t)
	  (if (kill-buffer (current-buffer))
	      ;; If `delete-window' failed before, we rerun it to regenerate
	      ;; the error so it can be seen in the echo area.
	      (when (eq (selected-window) window-to-delete)
		(delete-window))))
      ;; If the buffer is not dead for some reason (probably because
      ;; of a `quit' signal), remove the hook again.
      (ignore-errors
       (with-current-buffer buffer-to-kill
	 (remove-hook 'kill-buffer-hook delete-window-hook t))))))

(defun quit-window (&optional kill window)
  "Quit WINDOW and bury its buffer.
With a prefix argument, kill the buffer instead.  WINDOW defaults
to the selected window.

If WINDOW is non-nil, dedicated, or a minibuffer window, delete
it and, if it's alone on its frame, its frame too.  Otherwise, or
if deleting WINDOW fails in any of the preceding cases, display
another buffer in WINDOW using `switch-to-buffer'.

Optional argument KILL non-nil means kill WINDOW's buffer.
Otherwise, bury WINDOW's buffer, see `bury-buffer'."
  (interactive "P")
  (let ((buffer (window-buffer window)))
    (if (or window
	    (window-minibuffer-p window)
	    (window-dedicated-p window))
	;; WINDOW is either non-nil, a minibuffer window, or dedicated;
	;; try to delete it.
	(let* ((window (or window (selected-window)))
	       (frame (window-frame window)))
	  (if (frame-root-window-p window)
	      ;; WINDOW is alone on its frame.
	      (delete-frame frame)
	    ;; There are other windows on its frame, delete WINDOW.
	    (delete-window window)))
      ;; Otherwise, switch to another buffer in the selected window.
      (switch-to-buffer nil))

    ;; Deal with the buffer.
    (if kill
	(kill-buffer buffer)
      (bury-buffer buffer))))

(defvar recenter-last-op nil
  "Indicates the last recenter operation performed.
Possible values: `top', `middle', `bottom', integer or float numbers.")

(defcustom recenter-positions '(middle top bottom)
  "Cycling order for `recenter-top-bottom'.
A list of elements with possible values `top', `middle', `bottom',
integer or float numbers that define the cycling order for
the command `recenter-top-bottom'.

Top and bottom destinations are `scroll-margin' lines the from true
window top and bottom.  Middle redraws the frame and centers point
vertically within the window.  Integer number moves current line to
the specified absolute window-line.  Float number between 0.0 and 1.0
means the percentage of the screen space from the top.  The default
cycling order is middle -> top -> bottom."
  :type '(repeat (choice
		  (const :tag "Top" top)
		  (const :tag "Middle" middle)
		  (const :tag "Bottom" bottom)
		  (integer :tag "Line number")
		  (float :tag "Percentage")))
  :version "23.2"
  :group 'windows)

(defun recenter-top-bottom (&optional arg)
  "Move current buffer line to the specified window line.
With no prefix argument, successive calls place point according
to the cycling order defined by `recenter-positions'.

A prefix argument is handled like `recenter':
 With numeric prefix ARG, move current line to window-line ARG.
 With plain `C-u', move current line to window center."
  (interactive "P")
  (cond
   (arg (recenter arg))			; Always respect ARG.
   (t
    (setq recenter-last-op
	  (if (eq this-command last-command)
	      (car (or (cdr (member recenter-last-op recenter-positions))
		       recenter-positions))
	    (car recenter-positions)))
    (let ((this-scroll-margin
	   (min (max 0 scroll-margin)
		(truncate (/ (window-body-height) 4.0)))))
      (cond ((eq recenter-last-op 'middle)
	     (recenter))
	    ((eq recenter-last-op 'top)
	     (recenter this-scroll-margin))
	    ((eq recenter-last-op 'bottom)
	     (recenter (- -1 this-scroll-margin)))
	    ((integerp recenter-last-op)
	     (recenter recenter-last-op))
	    ((floatp recenter-last-op)
	     (recenter (round (* recenter-last-op (window-height))))))))))

(define-key global-map [?\C-l] 'recenter-top-bottom)

(defun move-to-window-line-top-bottom (&optional arg)
  "Position point relative to window.

With a prefix argument ARG, acts like `move-to-window-line'.

With no argument, positions point at center of window.
Successive calls position point at positions defined
by `recenter-positions'."
  (interactive "P")
  (cond
   (arg (move-to-window-line arg))	; Always respect ARG.
   (t
    (setq recenter-last-op
	  (if (eq this-command last-command)
	      (car (or (cdr (member recenter-last-op recenter-positions))
		       recenter-positions))
	    (car recenter-positions)))
    (let ((this-scroll-margin
	   (min (max 0 scroll-margin)
		(truncate (/ (window-body-height) 4.0)))))
      (cond ((eq recenter-last-op 'middle)
	     (call-interactively 'move-to-window-line))
	    ((eq recenter-last-op 'top)
	     (move-to-window-line this-scroll-margin))
	    ((eq recenter-last-op 'bottom)
	     (move-to-window-line (- -1 this-scroll-margin)))
	    ((integerp recenter-last-op)
	     (move-to-window-line recenter-last-op))
	    ((floatp recenter-last-op)
	     (move-to-window-line (round (* recenter-last-op (window-height))))))))))

(define-key global-map [?\M-r] 'move-to-window-line-top-bottom)

;;; Scrolling commands.

;;; Scrolling commands which does not signal errors at top/bottom
;;; of buffer at first key-press (instead moves to top/bottom
;;; of buffer).

(defcustom scroll-error-top-bottom nil
  "Move point to top/bottom of buffer before signalling a scrolling error.
A value of nil means just signal an error if no more scrolling possible.
A value of t means point moves to the beginning or the end of the buffer
\(depending on scrolling direction) when no more scrolling possible.
When point is already on that position, then signal an error."
  :type 'boolean
  :group 'scrolling
  :version "24.1")

(defun scroll-up-command (&optional arg)
  "Scroll text of selected window upward ARG lines; or near full screen if no ARG.
If `scroll-error-top-bottom' is non-nil and `scroll-up' cannot
scroll window further, move cursor to the bottom line.
When point is already on that position, then signal an error.
A near full screen is `next-screen-context-lines' less than a full screen.
Negative ARG means scroll downward.
If ARG is the atom `-', scroll downward by nearly full screen."
  (interactive "^P")
  (cond
   ((null scroll-error-top-bottom)
    (scroll-up arg))
   ((eq arg '-)
    (scroll-down-command nil))
   ((< (prefix-numeric-value arg) 0)
    (scroll-down-command (- (prefix-numeric-value arg))))
   ((eobp)
    (scroll-up arg))			; signal error
   (t
    (condition-case nil
	(scroll-up arg)
      (end-of-buffer
       (if arg
	   ;; When scrolling by ARG lines can't be done,
	   ;; move by ARG lines instead.
	   (forward-line arg)
	 ;; When ARG is nil for full-screen scrolling,
	 ;; move to the bottom of the buffer.
	 (goto-char (point-max))))))))

(put 'scroll-up-command 'scroll-command t)

(defun scroll-down-command (&optional arg)
  "Scroll text of selected window down ARG lines; or near full screen if no ARG.
If `scroll-error-top-bottom' is non-nil and `scroll-down' cannot
scroll window further, move cursor to the top line.
When point is already on that position, then signal an error.
A near full screen is `next-screen-context-lines' less than a full screen.
Negative ARG means scroll upward.
If ARG is the atom `-', scroll upward by nearly full screen."
  (interactive "^P")
  (cond
   ((null scroll-error-top-bottom)
    (scroll-down arg))
   ((eq arg '-)
    (scroll-up-command nil))
   ((< (prefix-numeric-value arg) 0)
    (scroll-up-command (- (prefix-numeric-value arg))))
   ((bobp)
    (scroll-down arg))			; signal error
   (t
    (condition-case nil
	(scroll-down arg)
      (beginning-of-buffer
       (if arg
	   ;; When scrolling by ARG lines can't be done,
	   ;; move by ARG lines instead.
	   (forward-line (- arg))
	 ;; When ARG is nil for full-screen scrolling,
	 ;; move to the top of the buffer.
	 (goto-char (point-min))))))))

(put 'scroll-down-command 'scroll-command t)

;;; Scrolling commands which scroll a line instead of full screen.

(defun scroll-up-line (&optional arg)
  "Scroll text of selected window upward ARG lines; or one line if no ARG.
If ARG is omitted or nil, scroll upward by one line.
This is different from `scroll-up-command' that scrolls a full screen."
  (interactive "p")
  (scroll-up (or arg 1)))

(put 'scroll-up-line 'scroll-command t)

(defun scroll-down-line (&optional arg)
  "Scroll text of selected window down ARG lines; or one line if no ARG.
If ARG is omitted or nil, scroll down by one line.
This is different from `scroll-down-command' that scrolls a full screen."
  (interactive "p")
  (scroll-down (or arg 1)))

(put 'scroll-down-line 'scroll-command t)


(defun scroll-other-window-down (lines)
  "Scroll the \"other window\" down.
For more details, see the documentation for `scroll-other-window'."
  (interactive "P")
  (scroll-other-window
   ;; Just invert the argument's meaning.
   ;; We can do that without knowing which window it will be.
   (if (eq lines '-) nil
     (if (null lines) '-
       (- (prefix-numeric-value lines))))))

(defun beginning-of-buffer-other-window (arg)
  "Move point to the beginning of the buffer in the other window.
Leave mark at previous position.
With arg N, put point N/10 of the way from the true beginning."
  (interactive "P")
  (let ((orig-window (selected-window))
	(window (other-window-for-scrolling)))
    ;; We use unwind-protect rather than save-window-excursion
    ;; because the latter would preserve the things we want to change.
    (unwind-protect
	(progn
	  (select-window window)
	  ;; Set point and mark in that window's buffer.
	  (with-no-warnings
	   (beginning-of-buffer arg))
	  ;; Set point accordingly.
	  (recenter '(t)))
      (select-window orig-window))))

(defun end-of-buffer-other-window (arg)
  "Move point to the end of the buffer in the other window.
Leave mark at previous position.
With arg N, put point N/10 of the way from the true end."
  (interactive "P")
  ;; See beginning-of-buffer-other-window for comments.
  (let ((orig-window (selected-window))
	(window (other-window-for-scrolling)))
    (unwind-protect
	(progn
	  (select-window window)
	  (with-no-warnings
	   (end-of-buffer arg))
	  (recenter '(t)))
      (select-window orig-window))))

(defvar mouse-autoselect-window-timer nil
  "Timer used by delayed window autoselection.")

(defvar mouse-autoselect-window-position nil
  "Last mouse position recorded by delayed window autoselection.")

(defvar mouse-autoselect-window-window nil
  "Last window recorded by delayed window autoselection.")

(defvar mouse-autoselect-window-state nil
  "When non-nil, special state of delayed window autoselection.
Possible values are `suspend' \(suspend autoselection after a menu or
scrollbar interaction\) and `select' \(the next invocation of
'handle-select-window' shall select the window immediately\).")

(defun mouse-autoselect-window-cancel (&optional force)
  "Cancel delayed window autoselection.
Optional argument FORCE means cancel unconditionally."
  (unless (and (not force)
	       ;; Don't cancel for select-window or select-frame events
	       ;; or when the user drags a scroll bar.
	       (or (memq this-command
			 '(handle-select-window handle-switch-frame))
		   (and (eq this-command 'scroll-bar-toolkit-scroll)
			(memq (nth 4 (event-end last-input-event))
			      '(handle end-scroll)))))
    (setq mouse-autoselect-window-state nil)
    (when (timerp mouse-autoselect-window-timer)
      (cancel-timer mouse-autoselect-window-timer))
    (remove-hook 'pre-command-hook 'mouse-autoselect-window-cancel)))

(defun mouse-autoselect-window-start (mouse-position &optional window suspend)
  "Start delayed window autoselection.
MOUSE-POSITION is the last position where the mouse was seen as returned
by `mouse-position'.  Optional argument WINDOW non-nil denotes the
window where the mouse was seen.  Optional argument SUSPEND non-nil
means suspend autoselection."
  ;; Record values for MOUSE-POSITION, WINDOW, and SUSPEND.
  (setq mouse-autoselect-window-position mouse-position)
  (when window (setq mouse-autoselect-window-window window))
  (setq mouse-autoselect-window-state (when suspend 'suspend))
  ;; Install timer which runs `mouse-autoselect-window-select' after
  ;; `mouse-autoselect-window' seconds.
  (setq mouse-autoselect-window-timer
	(run-at-time
	 (abs mouse-autoselect-window) nil 'mouse-autoselect-window-select)))

(defun mouse-autoselect-window-select ()
  "Select window with delayed window autoselection.
If the mouse position has stabilized in a non-selected window, select
that window.  The minibuffer window is selected only if the minibuffer is
active.  This function is run by `mouse-autoselect-window-timer'."
  (ignore-errors
   (let* ((mouse-position (mouse-position))
	  (window
	   (ignore-errors
	    (window-at (cadr mouse-position) (cddr mouse-position)
		       (car mouse-position)))))
     (cond
      ((or (menu-or-popup-active-p)
	   (and window
		(not (coordinates-in-window-p (cdr mouse-position) window))))
       ;; A menu / popup dialog is active or the mouse is on the scroll-bar
       ;; of WINDOW, temporarily suspend delayed autoselection.
       (mouse-autoselect-window-start mouse-position nil t))
      ((eq mouse-autoselect-window-state 'suspend)
       ;; Delayed autoselection was temporarily suspended, reenable it.
       (mouse-autoselect-window-start mouse-position))
      ((and window (not (eq window (selected-window)))
	    (or (not (numberp mouse-autoselect-window))
		(and (> mouse-autoselect-window 0)
		     ;; If `mouse-autoselect-window' is positive, select
		     ;; window if the window is the same as before.
		     (eq window mouse-autoselect-window-window))
		;; Otherwise select window if the mouse is at the same
		;; position as before.  Observe that the first test after
		;; starting autoselection usually fails since the value of
		;; `mouse-autoselect-window-position' recorded there is the
		;; position where the mouse has entered the new window and
		;; not necessarily where the mouse has stopped moving.
		(equal mouse-position mouse-autoselect-window-position))
	    ;; The minibuffer is a candidate window if it's active.
	    (or (not (window-minibuffer-p window))
		(eq window (active-minibuffer-window))))
       ;; Mouse position has stabilized in non-selected window: Cancel
       ;; delayed autoselection and try to select that window.
       (mouse-autoselect-window-cancel t)
       ;; Select window where mouse appears unless the selected window is the
       ;; minibuffer.  Use `unread-command-events' in order to execute pre-
       ;; and post-command hooks and trigger idle timers.  To avoid delaying
       ;; autoselection again, set `mouse-autoselect-window-state'."
       (unless (window-minibuffer-p (selected-window))
	 (setq mouse-autoselect-window-state 'select)
	 (setq unread-command-events
	       (cons (list 'select-window (list window))
		     unread-command-events))))
      ((or (and window (eq window (selected-window)))
	   (not (numberp mouse-autoselect-window))
	   (equal mouse-position mouse-autoselect-window-position))
       ;; Mouse position has either stabilized in the selected window or at
       ;; `mouse-autoselect-window-position': Cancel delayed autoselection.
       (mouse-autoselect-window-cancel t))
      (t
       ;; Mouse position has not stabilized yet, resume delayed
       ;; autoselection.
       (mouse-autoselect-window-start mouse-position window))))))

(defun handle-select-window (event)
  "Handle select-window events."
  (interactive "e")
  (let ((window (posn-window (event-start event))))
    (unless (or (not (window-live-p window))
		;; Don't switch if we're currently in the minibuffer.
		;; This tries to work around problems where the
		;; minibuffer gets unselected unexpectedly, and where
		;; you then have to move your mouse all the way down to
		;; the minibuffer to select it.
		(window-minibuffer-p (selected-window))
		;; Don't switch to minibuffer window unless it's active.
		(and (window-minibuffer-p window)
		     (not (minibuffer-window-active-p window)))
		;; Don't switch when autoselection shall be delayed.
		(and (numberp mouse-autoselect-window)
		     (not (zerop mouse-autoselect-window))
		     (not (eq mouse-autoselect-window-state 'select))
		     (progn
		       ;; Cancel any delayed autoselection.
		       (mouse-autoselect-window-cancel t)
		       ;; Start delayed autoselection from current mouse
		       ;; position and window.
		       (mouse-autoselect-window-start (mouse-position) window)
		       ;; Executing a command cancels delayed autoselection.
		       (add-hook
			'pre-command-hook 'mouse-autoselect-window-cancel))))
      (when mouse-autoselect-window
	;; Reset state of delayed autoselection.
	(setq mouse-autoselect-window-state nil)
	;; Run `mouse-leave-buffer-hook' when autoselecting window.
	(run-hooks 'mouse-leave-buffer-hook))
      (select-window window))))

(defun truncated-partial-width-window-p (&optional window)
  "Return non-nil if lines in WINDOW are specifically truncated due to its width.
WINDOW defaults to the selected window.
Return nil if WINDOW is not a partial-width window
 (regardless of the value of `truncate-lines').
Otherwise, consult the value of `truncate-partial-width-windows'
 for the buffer shown in WINDOW."
  (unless window
    (setq window (selected-window)))
  (unless (window-full-width-p window)
    (let ((t-p-w-w (buffer-local-value 'truncate-partial-width-windows
				       (window-buffer window))))
      (if (integerp t-p-w-w)
	  (< (window-width window) t-p-w-w)
	t-p-w-w))))

(define-key ctl-x-map "0" 'delete-window)
(define-key ctl-x-map "1" 'delete-other-windows)
(define-key ctl-x-map "2" 'split-window-above-each-other)
(define-key ctl-x-map "3" 'split-window-side-by-side)
(define-key ctl-x-map "o" 'other-window)
(define-key ctl-x-map "^" 'enlarge-window)
(define-key ctl-x-map "}" 'enlarge-window-horizontally)
(define-key ctl-x-map "{" 'shrink-window-horizontally)
(define-key ctl-x-map "-" 'shrink-window-if-larger-than-buffer)
(define-key ctl-x-map "+" 'balance-windows)
(define-key ctl-x-4-map "0" 'kill-buffer-and-window)

;;; window.el ends here
