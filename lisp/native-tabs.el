;;; native-tabs.el --- Support tabs in frames

;; Copyright (C) 2010 Free Software Foundation, Inc.

;; Author: Jan Djärv <jan.h.d@swipnet.se>
;; Maintainer: FSF
;; Keywords: tabs

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

;; This file provides the lisp part of Gtk+ native tabs.

;;; Code:

;;; Customizable variables

(declare-function tab-new "xfns.c" ())
(declare-function tab-delete "xfns.c" ())
(declare-function tab-delete-other "xfns.c" ())
(declare-function tab-next "xfns.c" ())
(declare-function tab-previous "xfns.c" ())

(defun find-file-new-tab (filename &optional wildcards)
  "Edit file FILENAME, in a new tab.

Like \\[find-file] (which see), but creates a new tab.

Interactively, the default if you just type RET is the current directory,
but the visited file name is available through the minibuffer history:
type M-n to pull it into the minibuffer.

Interactively, or if WILDCARDS is non-nil in a call from Lisp,
expand wildcards (if any) and visit multiple files."
  (interactive
   (find-file-read-args "Find file in new tab: "
                        (confirm-nonexistent-file-or-buffer)))
  (let ((value (find-file-noselect filename nil nil wildcards)))
    (tab-new)
    (delete-other-windows)
    (if (listp value)
	(progn
	  (setq value (nreverse value))
	  (cons (switch-to-buffer (car value))
		(mapcar 'switch-to-buffer (cdr value))))
      (switch-to-buffer value))))


(defun handle-tab-event (event)
  "Handle tab-event to change tabs on the frame in EVENT."
  (interactive "e")
  (let* ((n1 (nth 0 (cdr event)))
	 (n2 (nth 1 (cdr event)))
	 (type (car n2))
	 (frame (car n1))
	 (x (car (cdr n1)))
	 (y (cdr (cdr n1))))
    (if (eq type 2) 
	(let ((top y)
	      (left x)
	      (width (frame-pixel-width frame))
	      (height (frame-pixel-height frame))
	      (dw (x-display-pixel-width frame))
	      (dh (x-display-pixel-height frame)))
	  (if (< dw (+ left width))
	      (setq left (- dw width)))
	  (if (< dh (+ top height))
	      (setq top (- dh height)))
	  (message "handle-tab-event, top/left %s/%s" top left)
	  (make-frame 
	   (list (cons 'width (frame-parameter frame 'width))
		 (cons 'height(frame-parameter frame 'height))
		 (cons 'top top)
		 (cons 'left left)))))))

(if (featurep 'tabs)
    (progn
      (define-key special-event-map [tab-event]
	'handle-tab-event)
      (global-set-key "\C-x7\C-f" 'find-file-new-tab)
      (global-set-key "\C-x70" 'tab-delete)
      (global-set-key "\C-x71" 'tab-delete-other)
      (global-set-key "\C-x72" 'tab-new)
      (global-set-key "\C-x7f" 'find-file-new-tab)
      (global-set-key "\C-x7o" 'tab-next)
      (global-set-key "\C-x7n" 'tab-next)
      (global-set-key "\C-x7p" 'tab-previous)))

