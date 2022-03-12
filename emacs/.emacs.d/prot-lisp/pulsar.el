;;; pulsar.el --- Pulse line after running select functions -*- lexical-binding: t -*-

;; Copyright (C) 2022  Free Software Foundation, Inc.

;; Author: Protesilaos Stavrou <info@protesilaos.com>
;; URL: https://protesilaos.com/emacs/pulsar
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at
;; your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This is a small package that temporarily highlights the current line
;; after a given function is invoked.  The affected functions are defined
;; in the user option `pulsar-pulse-functions'.  What Pulsar does is set up
;; an advice so that those functions run a hook after they are called.
;; The pulse effect is added there (`pulsar-after-function-hook').
;; 
;; The duration of the highlight is determined by `pulsar-delay'.  While
;; the applicable face is specified in `pulsar-face'.
;; 
;; To highlight the current line on demand, use `pulsar-pulse-line'.
;; 
;; Pulsar depends on the built-in `pulse.el' library.
;;
;; Why the name "pulsar"?  It sounds like "pulse" and is a recognisable
;; word.  Though if you need a backronym, consider "Pulsar
;; Unquestionably Luminates, Strictly Absent the Radiation".

;;; Code:

(require 'pulse)

(defgroup pulsar ()
  "Extensions for `pulse.el'."
  :group 'editing)

;;;; User options and faces

(defcustom pulsar-pulse-functions
  '(recenter-top-bottom
    move-to-window-line-top-bottom
    reposition-window
    bookmark-jump
    other-window
    forward-page
    backward-page
    scroll-up-command
    scroll-down-command
    org-next-visible-heading
    org-previous-visible-heading
    org-forward-heading-same-level
    org-backward-heading-same-level
    outline-backward-same-level
    outline-forward-same-level
    outline-next-visible-heading
    outline-previous-visible-heading
    outline-up-heading)
  "Functions that highlight the current line after invocation.
This only takes effect when `pulsar-setup' is invoked (e.g. while
setting up `pulsar.el').

Any update to this user option outside of Custom (e.g. with
`setq') requires a re-run of `pulsar-setup'.  Whereas functions
such as `customize-set-variable' do that automatically."
  :type '(repeat function)
  :initialize #'custom-initialize-default
  :set (lambda (symbol value)
         (if (eq value (default-value symbol))
             (set-default symbol value)
           (pulsar-setup 'reverse)
           (set-default symbol value)
           (pulsar-setup)))
  :group 'pulsar)

(defcustom pulsar-face 'pulse-highlight-start-face
  "Face to use for the pulse line.
The default is `pulse-highlight-start-face', though users can
select one among `pulsar-red', `pulsar-green', `pulsar-yellow',
`pulsar-blue', `pulsar-magenta', `pulsar-cyan', or any other face
that has a background attribute."
  :type '(radio (face :tag "Standard pulse.el face" pulse-highlight-start-face)
                (face :tag "Red style" pulsar-red)
                (face :tag "Green style" pulsar-green)
                (face :tag "Yellow style" pulsar-yellow)
                (face :tag "Blue style" pulsar-blue)
                (face :tag "Magenta style" pulsar-magenta)
                (face :tag "Cyan style" pulsar-cyan)
                (face :tag "Other face (must have a background)"))
  :group 'pulsar)

(defcustom pulsar-delay 0.05
  "Duration in seconds of the active pulse highlight."
  :type 'number
  :group 'pulsar)

(defgroup pulsar-faces ()
  "Faces for `pulsar.el'."
  :group 'pulsar)

(defface pulsar-red
  '((default :extend t)
    (((class color) (min-colors 88) (background light))
     :background "#ffcccc")
    (((class color) (min-colors 88) (background dark))
     :background "#77002a")
    (t :inverse-video t))
  "Alternative red face for `pulsar-face'."
  :group 'pulsar-faces)

(defface pulsar-green
  '((default :extend t)
    (((class color) (min-colors 88) (background light))
     :background "#aceaac")
    (((class color) (min-colors 88) (background dark))
     :background "#00422a")
    (t :inverse-video t))
  "Alternative green face for `pulsar-face'."
  :group 'pulsar-faces)

(defface pulsar-yellow
  '((default :extend t)
    (((class color) (min-colors 88) (background light))
     :background "#fff29a")
    (((class color) (min-colors 88) (background dark))
     :background "#693200")
    (t :inverse-video t))
  "Alternative yellow face for `pulsar-face'."
  :group 'pulsar-faces)

(defface pulsar-blue
  '((default :extend t)
    (((class color) (min-colors 88) (background light))
     :background "#8fcfff")
    (((class color) (min-colors 88) (background dark))
     :background "#242679")
    (t :inverse-video t))
  "Alternative blue face for `pulsar-face'."
  :group 'pulsar-faces)

(defface pulsar-magenta
  '((default :extend t)
    (((class color) (min-colors 88) (background light))
     :background "#ffccff")
    (((class color) (min-colors 88) (background dark))
     :background "#71206a")
    (t :inverse-video t))
  "Alternative magenta face for `pulsar-face'."
  :group 'pulsar-faces)

(defface pulsar-cyan
  '((default :extend t)
    (((class color) (min-colors 88) (background light))
     :background "#8eecf4")
    (((class color) (min-colors 88) (background dark))
     :background "#004065")
    (t :inverse-video t))
  "Alternative cyan face for `pulsar-face'."
  :group 'pulsar-faces)

;;;; Functions and commands

(defun pulsar--indentation-only-line-p ()
  "Return non-nil if current line has only indentation."
  (save-excursion
    (goto-char (point-at-bol))
    (and (not (bobp))
	     (or (beginning-of-line 1) t)
	     (save-match-data
	       (looking-at "^[\s\t]+")))))

(defun pulsar--buffer-end-p ()
  "Return non-nil if point is at the end of the buffer."
  (unless (pulsar--indentation-only-line-p)
    (or (eobp) (eq (point) (point-max)))))

(defun pulsar--start ()
  "Return appropriate line start."
  (if (pulsar--buffer-end-p)
      (line-beginning-position 0)
    (line-beginning-position)))

(defun pulsar--end ()
  "Return appropriate line end."
  (if (pulsar--buffer-end-p)
      (line-beginning-position 1)
    (line-beginning-position 2)))

;;;###autoload
(defun pulsar-pulse-line ()
  "Temporarily highlight the current line with optional FACE."
  (interactive)
  (let ((pulse-delay pulsar-delay))
    (pulse-momentary-highlight-region (pulsar--start) (pulsar--end) pulsar-face)))

(defvar pulsar-after-function-hook nil
  "Hook that runs after any function in `pulsar-pulse-functions'.")

(defun pulsar--add-hook (&rest _)
  "Run `pulsar-after-function-hook'."
  (run-hooks 'pulsar-after-function-hook))

;;;###autoload
(defun pulsar-setup (&optional reverse)
  "Set up pulsar for select functions.
This adds the `pulsar-after-function-hook' to every command listed
in the `pulsar-pulse-functions'.  If the list is updated, this
command needs to be invoked again.

With optional non-nil REVERSE argument, remove the advice that
sets up the aforementioned hook."
  (cond
   (reverse
    (dolist (fn pulsar-pulse-functions)
      (advice-remove fn #'pulsar--add-hook))
    (remove-hook 'pulsar-after-function-hook #'pulsar-pulse-line))
   (t
    (dolist (fn pulsar-pulse-functions)
      (advice-add fn :after #'pulsar--add-hook))
    (add-hook 'pulsar-after-function-hook #'pulsar-pulse-line))))

(provide 'pulsar)
;;; pulsar.el ends here