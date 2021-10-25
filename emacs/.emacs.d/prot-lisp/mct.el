;;; mct.el --- Minibuffer and Completions in Tandem -*- lexical-binding: t -*-

;; Copyright (C) 2021  Free Software Foundation, Inc.

;; Author: Protesilaos Stavrou <info@protesilaos.com>
;; URL: https://gitlab.com/protesilaos/mct.el
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))

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
;; MCT enhances the default Emacs completion.  It makes the minibuffer
;; and Completions' buffer work together and look like a vertical
;; completion UI.
;;
;; Read the documentation for basic usage and configuration.

;;; Code:

;;;; General utilities

(defgroup mct ()
  "Extensions for the minibuffer."
  :group 'minibuffer)

(defcustom mct-completion-windows-regexp
  "\\`\\*Completions.*\\*\\'"
  "Regexp to match window names with completion candidates.
Used by `mct--get-completion-window'."
  :type 'string
  :group 'mct)

(defcustom mct-remove-shadowed-file-names nil
  "Delete shadowed parts of file names.

For example, if the user types ~/ after a long path name,
everything preceding the ~/ is removed so the interactive
selection process starts again from the user's $HOME.

Only works when variable `file-name-shadow-mode' is non-nil."
  :type 'boolean
  :group 'mct)

(defcustom mct-hide-completion-mode-line nil
  "Do not show a mode line in the Completions' buffer."
  :type 'boolean
  :group 'mct)

(defcustom mct-show-completion-line-numbers nil
  "Display line numbers in the Completions' buffer."
  :type 'boolean
  :group 'mct)

(defcustom mct-apply-completion-stripes nil
  "Display alternating backgrounds the Completions' buffer."
  :type 'boolean
  :group 'mct)

(defcustom mct-live-completion t
  "Automatically display the Completions buffer.

When disabled, the user has to manually request completions,
using the regular activating commands.  Note that
`mct-completion-passlist' overrides this option, while taking
precedence over `mct-completion-blocklist'.

Live updating is subject to `mct-minimum-input'."
  :type 'boolean
  :group 'mct)

(defcustom mct-minimum-input 3
  "Live update completions when input is >= N.

Setting this to a value greater than 1 can help reduce the total
number of candidates that are being computed."
  :type 'natnum
  :group 'mct)

(defcustom mct-live-update-delay 0.3
  "Delay in seconds before updating the Completions' buffer.

Set this to 0 to disable the delay."
  :type 'number
  :group 'mct)

(defcustom mct-completion-blocklist nil
  "Commands that do not do live updating of completions.

A less drastic measure is to set `mct-minimum-input'
to an appropriate value.

The Completions' buffer can still be accessed with commands that
place it in a window (such as `mct-list-completions-toggle',
`mct-switch-to-completions-top')."
  :type '(repeat symbol)
  :group 'mct)

(defcustom mct-completion-passlist nil
  "Commands that do live updating of completions from the start.

This means that they ignore `mct-minimum-input' and
the inherent constraint of updating the Completions' buffer only
upon user input.  Furthermore, they also bypass any possible
delay introduced by `mct-live-update-delay'."
  :type '(repeat symbol)
  :group 'mct)

(defcustom mct-display-buffer-action
  '((display-buffer-reuse-window display-buffer-at-bottom))
  "The action used to display the Completions' buffer.

The value has the form (FUNCTION . ALIST), where FUNCTIONS is
either an \"action function\" or a possibly empty list of action
functions.  ALIST is a possibly empty \"action alist\".

Sample configuration:

    (setq mct-display-buffer-action
          (quote ((display-buffer-reuse-window
                   display-buffer-in-side-window)
                  (side . left)
                  (slot . 99)
                  (window-width . 0.3))))

See Info node `(elisp) Displaying Buffers' for more details
and/or the documentation string of `display-buffer'."
  :type '(cons (choice (function :tag "Display Function")
                       (repeat :tag "Display Functions" function))
               alist)
  :group 'mct)

(defcustom mct-completions-format 'one-column
  "The appearance and sorting used by `mct-mode'.
See `completions-format' for possible values.

NOTE that setting this option with `setq' requires a restart of
`mct-mode'."
  :set (lambda (var val)
         (when (bound-and-true-p mct-mode)
           (setq completions-format val))
         (set var val))
  :type '(choice (const horizontal) (const vertical) (const one-column))
  :group 'mct)

;;;; Basic helper functions

;; Copied from icomplete.el
(defun mct--field-beg ()
  "Determine beginning of completion."
  (if (window-minibuffer-p)
      (minibuffer-prompt-end)
    (nth 0 completion-in-region--data)))

;; Copied from icomplete.el
(defun mct--field-end ()
  "Determine end of completion."
  (if (window-minibuffer-p)
      (point-max)
    (nth 1 completion-in-region--data)))

;; Copied from icomplete.el
(defun mct--completion-category ()
  "Return completion category."
  (let* ((beg (mct--field-beg))
         (md (when (window-minibuffer-p) (completion--field-metadata beg))))
    (alist-get 'category (cdr md))))

;;;; Basics of intersection between minibuffer and Completions' buffer

(defface mct-hl-line
  '((default :extend t)
    (((class color) (min-colors 88) (background light))
     :background "#b0d8ff" :foreground "#000000")
    (((class color) (min-colors 88) (background dark))
     :background "#103265" :foreground "#ffffff")
    (t :inherit highlight))
  "Face for current line in the completions' buffer."
  :group 'mct)

(defface mct-line-number
  '((default :inherit default)
    (((class color) (min-colors 88) (background light))
     :background "#f2eff3" :foreground "#252525")
    (((class color) (min-colors 88) (background dark))
     :background "#151823" :foreground "#dddddd")
    (t :inverse-video t))
  "Face for line numbers in the completions' buffer."
  :group 'mct)

(defface mct-line-number-current-line
  '((default :inherit default)
    (((class color) (min-colors 88) (background light))
     :background "#8ac7ff" :foreground "#000000")
    (((class color) (min-colors 88) (background dark))
     :background "#142a79" :foreground "#ffffff")
    (t :inverse-video t))
  "Face for current line number in the completions' buffer."
  :group 'mct)

(declare-function display-line-numbers-mode "display-line-numbers")
(declare-function face-remap-remove-relative "face-remap" (cookie))

(defun mct--display-line-numbers ()
  "Set up line numbers for the completions' buffer.
Add this to `completion-list-mode-hook'."
  (when (and (derived-mode-p 'completion-list-mode)
             mct-show-completion-line-numbers)
    (face-remap-add-relative 'line-number 'mct-line-number)
    (face-remap-add-relative 'line-number-current-line
                             'mct-line-number-current-line)
    (display-line-numbers-mode 1)))

(defun mct--hl-line ()
  "Set up line highlighting for the completions' buffer.
Add this to `completion-list-mode-hook'."
  (when (and (derived-mode-p 'completion-list-mode)
             (eq mct-completions-format 'one-column))
    (face-remap-add-relative 'hl-line 'mct-hl-line)
    (hl-line-mode 1)))

;; Thanks to Omar Antolín Camarena for recommending the use of
;; `cursor-sensor-functions' and the concomitant hook with
;; `cursor-censor-mode' instead of the dirty hacks I had before to
;; prevent the cursor from moving to that position where no completion
;; candidates could be found at point (e.g. it would break `embark-act'
;; as it could not read the topmost candidate when point was at the
;; beginning of the line, unless the point was moved forward).
(defun mct--clean-completions ()
  "Keep only completion candidates in the Completions."
  (with-current-buffer standard-output
    (let ((inhibit-read-only t))
      (goto-char (point-min))
      (delete-region (point-at-bol) (1+ (point-at-eol)))
      (insert (propertize " "
                          'cursor-sensor-functions
                          (list
                           (lambda (_win prev dir)
                             (when (eq dir 'entered)
                               (goto-char prev))))))
      (put-text-property (point-min) (point) 'invisible t))))

(defun mct--fit-completions-window ()
  "Fit Completions' buffer to its window."
  (when-let ((window (mct--get-completion-window)))
    (with-current-buffer (window-buffer window)
      (setq-local window-resize-pixelwise t))
    (fit-window-to-buffer window (floor (frame-height) 2) 1)))

(defun mct--input-string ()
  "Return the contents of the minibuffer as a string."
  (buffer-substring-no-properties (minibuffer-prompt-end) (point-max)))

(defun mct--minimum-input ()
  "Test for minimum requisite input for live completions.
See `mct-minimum-input'."
  (>= (length (mct--input-string)) mct-minimum-input))

;;;;; Live-updating Completions' buffer

;; Adapted from Omar Antolín Camarena's live-completions library:
;; <https://github.com/oantolin/live-completions>.
(defun mct--live-completions (&rest _)
  "Update the *Completions* buffer.
Meant to be added to `after-change-functions'."
  (when (minibufferp) ; skip if we've exited already
    (let ((while-no-input-ignore-events '(selection-request)))
      (while-no-input
        (if (mct--minimum-input)
            (condition-case nil
                (save-match-data
                  (save-excursion
                    (goto-char (point-max))
                    (let ((inhibit-message t)
                          ;; don't ring the bell in `minibuffer-completion-help'
                          ;; when <= 1 completion exists.
                          (ring-bell-function #'ignore))
                      (mct--show-completions))))
              (quit (abort-recursive-edit)))
          (minibuffer-hide-completions))))))

(defun mct--live-completions-timer (&rest _)
  "Update Completions with `mct-live-update-delay'."
  (let ((delay mct-live-update-delay))
    (when (>= delay 0)
      (run-with-idle-timer delay nil #'mct--live-completions))))

(defun mct--setup-completions ()
  "Set up the completions' buffer."
  (cond
   ((memq this-command mct-completion-passlist)
    (setq-local mct-minimum-input 0)
    (setq-local mct-live-update-delay 0)
    (mct--show-completions)
    (add-hook 'after-change-functions #'mct--live-completions nil t))
   ((null mct-live-completion))
   ((not (memq this-command mct-completion-blocklist))
    (add-hook 'after-change-functions #'mct--live-completions-timer nil t))))

;;;;; Alternating backgrounds (else "stripes")

;; Based on `stripes.el' (maintained by Štěpán Němec) and the
;; `embark-collect-zebra-minor-mode' from Omar Antolín Camarena's
;; Embark:
;;
;; 1. <https://gitlab.com/stepnem/stripes-el>
;; 2. <https://github.com/oantolin/embark>
(defface mct-stripe
  '((default :extend t)
    (((class color) (min-colors 88) (background light))
     :background "#f0f0f0")
    (((class color) (min-colors 88) (background dark))
     :background "#191a1b"))
  "Face for alternating backgrounds in the Completions' buffer."
  :group 'mct)

(defun mct--remove-stripes ()
  "Remove `mct-stripe' overlays."
  (remove-overlays nil nil 'face 'mct-stripe))

(defun mct--add-stripes ()
  "Overlay alternate rows with the `mct-stripe' face."
  (when (derived-mode-p 'completion-list-mode)
    (mct--remove-stripes)
    (save-excursion
      (goto-char (point-min))
      (when (overlays-at (point)) (forward-line))
      (while (not (eobp))
        (condition-case nil
            (forward-line 1)
          (user-error (goto-char (point-max))))
        (unless (eobp)
          (let ((pt (point))
                (overlay))
            (condition-case nil
                (forward-line 1)
              (user-error (goto-char (point-max))))
            ;; We set the overlay this way and give it a low priority so
            ;; that `hl-line-mode' and/or the active region can override
            ;; it.
            (setq overlay (make-overlay pt (point)))
            (overlay-put overlay 'face 'mct-stripe)
            (overlay-put overlay 'priority -100)))))))

;;;; Commands and helper functions

;;;;; Focus minibuffer and/or show completions

;;;###autoload
(defun mct-focus-minibuffer ()
  "Focus the active minibuffer."
  (interactive nil mct-mode)
  (when-let ((mini (active-minibuffer-window)))
    (select-window mini)))

(defun mct--get-completion-window ()
  "Find a live window showing completion candidates."
  (get-window-with-predicate
   (lambda (window)
     (string-match-p
      mct-completion-windows-regexp
      (buffer-name (window-buffer window))))))

(defun mct--show-completions ()
  "Show the completions' buffer."
  (let ((display-buffer-alist
         (cons (cons mct-completion-windows-regexp mct-display-buffer-action)
               display-buffer-alist)))
    (save-excursion (minibuffer-completion-help)))
  (mct--fit-completions-window))

;;;###autoload
(defun mct-focus-mini-or-completions ()
  "Focus the active minibuffer or the completions' window.

If both the minibuffer and the Completions are present, this
command will first move per invocation to the former, then the
latter, and then continue to switch between the two.

The continuous switch is essentially the same as running
`mct-focus-minibuffer' and `switch-to-completions' in
succession.

What constitutes a completions' window is ultimately determined
by `mct-completion-windows-regexp'."
  (interactive nil mct-mode)
  (let* ((mini (active-minibuffer-window))
         (completions (mct--get-completion-window)))
    (cond
     ((and mini (not (minibufferp)))
      (select-window mini nil))
     ((and completions (not (eq (selected-window) completions)))
      (select-window completions nil)))))

;;;###autoload
(defun mct-list-completions-toggle ()
  "Toggle the presentation of the completions' buffer."
  (interactive nil mct-mode)
  (if (mct--get-completion-window)
      (minibuffer-hide-completions)
    (mct--show-completions)))

;;;;; Commands for file completion

;; Adaptation of `icomplete-fido-backward-updir'.
(defun mct-backward-updir ()
  "Delete char before point or go up a directory."
  (interactive nil mct-mode)
  (if (and (eq (char-before) ?/)
           (eq (mct--completion-category) 'file))
      (save-excursion
        (goto-char (1- (point)))
        (when (search-backward "/" (minibuffer-prompt-end) t)
          (delete-region (1+ (point)) (point-max))))
    (call-interactively 'backward-delete-char)))

;;;;; Cyclic motions between minibuffer and completions' buffer

(defun mct--first-completion-point ()
  "Find the `point' of the first completion."
  (save-excursion
    (goto-char (point-min))
    (next-completion 1)
    (point)))

(defun mct--last-completion-point ()
  "Find the `point' of the last completion."
  (save-excursion
    (goto-char (point-max))
    (next-completion -1)
    (point)))

(defun mct--completions-line-boundary (boundary)
  "Determine if current line has reached BOUNDARY.
BOUNDARY is a line position at the top or bottom of the
Completions' buffer.  See `mct--first-completion-point' or
`mct--last-completion-point'.

This check only applies when `completions-format' is not assigned
a `one-column' value."
  (and (= (line-number-at-pos) (line-number-at-pos boundary))
       (not (eq completions-format 'one-column))))

(defun mct--completions-no-completion-line-p (arg)
  "Check if ARGth line has a completion candidate."
  (save-excursion
    (vertical-motion arg)
    (get-text-property (point) 'completion--string)))

(defun mct--switch-to-completions ()
  "Subroutine for switching to the completions' buffer."
  (unless (mct--get-completion-window)
    (mct--show-completions))
  (switch-to-completions))

(defun mct--restore-old-point-in-grid (line)
  "Restore old point in window if LINE is on its line."
  (unless (eq completions-format 'one-column)
    (let (old-line old-point)
      (when-let ((window (mct--get-completion-window)))
        (setq old-point (window-old-point window)
              old-line (line-number-at-pos old-point))
        (when (= (line-number-at-pos line) old-line)
          (goto-char old-point))))))

(defun mct-switch-to-completions-top ()
  "Switch to the top of the completions' buffer."
  (interactive nil mct-mode)
  (mct--switch-to-completions)
  (goto-char (mct--first-completion-point))
  (mct--restore-old-point-in-grid (point)))

(defun mct-switch-to-completions-bottom ()
  "Switch to the bottom of the completions' buffer."
  (interactive nil mct-mode)
  (mct--switch-to-completions)
  (goto-char (point-max))
  (next-completion -1)
  (goto-char (point-at-bol))
  (mct--restore-old-point-in-grid (point))
  (recenter
   (- -1
      (min (max 0 scroll-margin)
           (truncate (/ (window-body-height) 4.0))))
   t))

(defun mct--bottom-of-completions-p (arg)
  "Test if point is at the notional bottom of the Completions.
ARG is a numeric argument for `next-completion', as described in
`mct-next-completion-or-mini'."
  (or (eobp)
      (mct--completions-line-boundary (mct--last-completion-point))
      (= (save-excursion (next-completion arg) (point)) (point-max))
      ;; The empty final line case...
      (save-excursion
        (goto-char (point-at-bol))
        (and (not (bobp))
	         (or (beginning-of-line (1+ arg)) t)
	         (save-match-data
	           (looking-at "[\s\t]*$"))))))

(defun mct-next-completion-or-mini (&optional arg)
  "Move to the next completion or switch to the minibuffer.
This performs a regular motion for optional ARG lines, but when
point can no longer move in that direction it switches to the
minibuffer."
  (interactive "p" mct-mode)
  (cond
   ((mct--bottom-of-completions-p (or arg 1))
    (mct-focus-minibuffer))
   (t
    (if (not (eq completions-format 'one-column))
        ;; Retaining the column number ensures that things work
        ;; intuitively in a grid view.
        (let ((col (current-column)))
          ;; The `unless' is meant to skip past lines that do not
          ;; contain completion candidates, such as those with
          ;; `completions-group-format'.
          (unless (mct--completions-no-completion-line-p (or arg 1))
            (if arg
                (setq arg (1+ arg))
              (setq arg 2)))
          (vertical-motion (or arg 1))
          (unless (eq col (save-excursion (goto-char (point-at-bol)) (current-column)))
            (line-move-to-column col)))
      (next-completion (or arg 1))))
   (setq this-command 'next-line)))

(defun mct--top-of-completions-p (arg)
  "Test if point is at the notional top of the Completions.
ARG is a numeric argument for `previous-completion', as described in
`mct-previous-completion-or-mini'."
  (or (bobp)
      (mct--completions-line-boundary (mct--first-completion-point))
      (= (save-excursion (previous-completion arg) (point)) (point-min))))

(defun mct-previous-completion-or-mini (&optional arg)
  "Move to the next completion or switch to the minibuffer.
This performs a regular motion for optional ARG lines, but when
point can no longer move in that direction it switches to the
minibuffer."
  (interactive "p" mct-mode)
  (cond
   ((mct--top-of-completions-p (if (natnump arg) arg 1))
    (mct-focus-minibuffer))
   ((if (not (eq completions-format 'one-column))
        ;; Retaining the column number ensures that things work
        ;; intuitively in a grid view.
        (let ((col (current-column)))
          ;; The `unless' is meant to skip past lines that do not
          ;; contain completion candidates, such as those with
          ;; `completions-group-format'.
          (unless (mct--completions-no-completion-line-p (or (- arg) -1))
            (if arg
                (setq arg (1+ arg))
              (setq arg 2)))
          (vertical-motion (or (- arg) -1))
          (unless (eq col (save-excursion (goto-char (point-at-bol)) (current-column)))
            (line-move-to-column col)))
      (previous-completion (if (natnump arg) arg 1))))))

;;;;; Candidate selection

(defun mct-choose-completion-exit ()
  "Run `choose-completion' in the Completions buffer and exit."
  (interactive nil mct-mode)
  (when (and (derived-mode-p 'completion-list-mode)
             (active-minibuffer-window))
    (choose-completion)
    (minibuffer-force-complete-and-exit)))

(defvar display-line-numbers-mode)

(defun mct--line-completion (n)
  "Select completion on Nth line."
  (with-current-buffer (window-buffer (mct--get-completion-window))
    (goto-char (point-min))
    (forward-line (1- n))
    (mct-choose-completion-exit)))

(defun mct--line-bounds (n)
  "Test if Nth line is in the buffer."
  (with-current-buffer (window-buffer (mct--get-completion-window))
    (let ((bounds (count-lines (point-min) (point-max))))
      (unless (<= n bounds)
        (user-error "%d is not within the buffer bounds (%d)" n bounds)))))

(defun mct-goto-line ()
  "Go to line N in the Completions' buffer."
  (interactive nil mct-mode)
  (let ((n (read-number "Line number: ")))
    (mct--line-bounds n)
    (select-window (mct--get-completion-window))
    (mct--line-completion n)))

(defun mct--line-number-selection ()
  "Show line numbers and select one of them."
  (with-current-buffer (window-buffer (mct--get-completion-window))
    (let ((mct-show-completion-line-numbers t))
      (if (bound-and-true-p display-line-numbers-mode)
          (mct-goto-line)
        (unwind-protect
            (progn
              (mct--display-line-numbers)
              (mct-goto-line))
          (display-line-numbers-mode -1))))))

(defun mct-choose-completion-number ()
  "Select completion candidate on line number with completion.

If the Completions' buffer is not visible, it is displayed.  Line
numbers are shown there for the duration of the operation (unless
`mct-show-completion-line-numbers' is non-nil, in which case they
are always visible).

This command can be invoked from either the minibuffer or the
Completions' buffer."
  (interactive nil mct-mode)
  (let ((mct-remove-shadowed-file-names t)
        (mct-live-update-delay most-positive-fixnum)
        (enable-recursive-minibuffers t))
    (unless (mct--get-completion-window)
      (mct--show-completions))
    (if (or (and (derived-mode-p 'completion-list-mode)
                 (active-minibuffer-window))
            (and (minibufferp)
                 (mct--get-completion-window)))
        (mct--line-number-selection))))

(defvar crm-completion-table)

(defun mct-choose-completion-dwim ()
  "Append to minibuffer when at `completing-read-multiple' prompt.
Otherwise behave like `mct-choose-completion-exit'."
  (interactive nil mct-mode)
  (when (and (derived-mode-p 'completion-list-mode)
             (active-minibuffer-window))
    (choose-completion)
    (with-current-buffer (window-buffer (active-minibuffer-window))
      (unless (eq (mct--completion-category) 'file)
        (minibuffer-force-complete))
      (when crm-completion-table
        ;; FIXME 2021-10-22: How to deal with commands that let-bind the
        ;; crm-separator?  For example: `org-set-tags-command'.
        (insert ",")
        (let ((inhibit-message t))
          (switch-to-completions))))))

(defun mct-edit-completion ()
  "Edit the candidate from the Completions in the minibuffer."
  (interactive nil mct-mode)
  (let (string)
    ;; BUG 2021-07-26: When we use `mct-list-completions-toggle'
    ;; the first line is active even without switching to the
    ;; Completions' buffer, so the user would expect that this command
    ;; would capture the candidate at that point.  It does not.
    ;;
    ;; If we focus the Completions' buffer at least once, then
    ;; everything works as expected.
    (when (or (and (minibufferp)
                   (mct--get-completion-window))
              (and (derived-mode-p 'completion-list-mode)
                   (active-minibuffer-window)))
      (with-current-buffer (window-buffer (mct--get-completion-window))
        (setq string (get-text-property (point) 'completion--string)))
      (if string
          (progn
            (select-window (active-minibuffer-window) nil)
            (delete-region (minibuffer-prompt-end) (point-max))
            (insert string))
        (user-error "Could not find completion at point")))))

;;;;; Miscellaneous commands

;; This is needed to circumvent `mct--clean-completions' with regard to
;; `cursor-sensor-functions'.
(defun mct-beginning-of-buffer ()
  "Go to the top of the Completions buffer."
  (interactive nil mct-mode)
  (goto-char (1+ (point-min))))

(defun mct-keyboard-quit-dwim ()
  "Control the exit behaviour for completions' buffers.

If in a completions' buffer and unless the region is active, run
`abort-recursive-edit'.  Otherwise run `keyboard-quit'.

If the region is active, deactivate it.  A second invocation of
this command is then required to abort the session."
  (interactive nil mct-mode)
  (when (derived-mode-p 'completion-list-mode)
    (if (use-region-p)
        (keyboard-quit)
      (abort-recursive-edit))))

;;;; Global minor mode setup

;;;;; Stylistic tweaks and refinements

;; Thanks to Omar Antolín Camarena for providing the messageless and
;; stealthily.  Source: <https://github.com/oantolin/emacs-config>.
(defun mct--messageless (fn &rest args)
  "Set `minibuffer-message-timeout' to 0.
Meant as advice around minibuffer completion FN with ARGS."
  (let ((minibuffer-message-timeout 0))
    (apply fn args)))

;; Copied from Daniel Mendler's `vertico' library:
;; <https://github.com/minad/vertico>.
(defun mct--crm-indicator (args)
  "Add prompt indicator to `completing-read-multiple' filter ARGS."
  (cons (concat "[CRM] " (car args)) (cdr args)))

;; Adapted from Omar Antolín Camarena's live-completions library:
;; <https://github.com/oantolin/live-completions>.
(defun mct--honor-inhibit-message (fn &rest args)
  "Skip applying FN to ARGS if `inhibit-message' is t.
Meant as `:around' advice for `minibuffer-message', which does
not honor minibuffer message."
  (unless inhibit-message
    (apply fn args)))

;; Note that this solves bug#45686:
;; <https://debbugs.gnu.org/cgi/bugreport.cgi?bug=45686>
(defun mct--stealthily (fn &rest args)
  "Prevent minibuffer default from counting as a modification.
Meant as advice for FN `minibuf-eldef-setup-minibuffer' with rest
ARGS."
  (let ((inhibit-modification-hooks t))
    (apply fn args)))

(defun mct--setup-completions-styles ()
  "Set up variables for default completions."
  (when mct-hide-completion-mode-line
    (setq-local mode-line-format nil))
  (if mct-apply-completion-stripes
      (mct--add-stripes)
    (mct--remove-stripes)))

(defun mct--truncate-lines-silently ()
  "Toggle line truncation without printing messages."
  (let ((inhibit-message t))
    (toggle-truncate-lines t)))

;;;;; Shadowed path

;; Adapted from icomplete.el
(defun mct--shadow-filenames (&rest _)
  "Hide shadowed file names."
  (let ((saved-point (point)))
    (when (and
           mct-remove-shadowed-file-names
           (eq (mct--completion-category) 'file)
           rfn-eshadow-overlay (overlay-buffer rfn-eshadow-overlay)
           (eq this-command 'self-insert-command)
           (= saved-point (mct--field-end))
           (or (>= (- (point) (overlay-end rfn-eshadow-overlay)) 2)
               (eq ?/ (char-before (- (point) 2)))))
      (delete-region (overlay-start rfn-eshadow-overlay)
                     (overlay-end rfn-eshadow-overlay)))))

(defun mct--setup-shadow-files ()
  "Set up shadowed file name deletion.
To be assigned to `minibuffer-setup-hook'."
  (add-hook 'after-change-functions #'mct--shadow-filenames nil t))

;;;;; Keymaps

(defvar mct-completion-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<tab>") #'choose-completion)
    (define-key map (kbd "M-v") #'scroll-down-command)
    (define-key map [remap goto-line] #'mct-choose-completion-number)
    (define-key map (kbd "M-e") #'mct-edit-completion)
    (define-key map [remap keyboard-quit] #'mct-keyboard-quit-dwim)
    (define-key map [remap next-line] #'mct-next-completion-or-mini)
    (define-key map (kbd "n") #'mct-next-completion-or-mini)
    (define-key map [remap previous-line] #'mct-previous-completion-or-mini)
    (define-key map (kbd "p") #'mct-previous-completion-or-mini)
    (define-key map (kbd "<return>") #'mct-choose-completion-exit)
    (define-key map (kbd "<M-return>") #'mct-choose-completion-dwim)
    (define-key map [remap beginning-of-buffer] #'mct-beginning-of-buffer)
    map)
  "Derivative of `completion-list-mode-map'.")

(defvar mct-minibuffer-local-completion-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-j") #'exit-minibuffer)
    (define-key map (kbd "<tab>") #'minibuffer-force-complete)
    (define-key map [remap goto-line] #'mct-choose-completion-number)
    (define-key map (kbd "M-e") #'mct-edit-completion)
    (define-key map (kbd "C-n") #'mct-switch-to-completions-top)
    (define-key map (kbd "<down>") #'mct-switch-to-completions-top)
    (define-key map (kbd "C-p") #'mct-switch-to-completions-bottom)
    (define-key map (kbd "<up>") #'mct-switch-to-completions-bottom)
    (define-key map (kbd "C-l") #'mct-list-completions-toggle)
    map)
  "Derivative of `minibuffer-local-completion-map'.")

(defvar mct-minibuffer-local-filename-completion-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<backspace>") #'mct-backward-updir)
    map)
  "Derivative of `minibuffer-local-filename-completion-map'.")

(defun mct--completion-list-mode-map ()
  "Hook to `completion-setup-hook'."
  (use-local-map
   (make-composed-keymap mct-completion-list-mode-map
                         (current-local-map))))

(defun mct--minibuffer-local-completion-map ()
  "Hook to `minibuffer-setup-hook'."
  (use-local-map
   (make-composed-keymap mct-minibuffer-local-completion-map
                         (current-local-map))))

(defun mct--minibuffer-local-filename-completion-map ()
  "Hook to `minibuffer-setup-hook'."
  (use-local-map
   (make-composed-keymap mct-minibuffer-local-filename-completion-map
                         (current-local-map))))

;;;;; mct-mode declaration

(declare-function minibuf-eldef-setup-minibuffer "minibuf-eldef")

(defvar mct--resize-mini-windows nil)
(defvar mct--completion-show-help nil)
(defvar mct--completion-auto-help nil)
(defvar mct--completions-format nil)

;;;###autoload
(define-minor-mode mct-mode
  "Set up opinionated default completion UI."
  :global t
  :group 'mct
  (if mct-mode
      (progn
        (setq mct--resize-mini-windows resize-mini-windows
              mct--completion-show-help completion-show-help
              mct--completion-auto-help completion-auto-help
              mct--completions-format completions-format)
        (setq resize-mini-windows t
              completion-show-help nil
              completion-auto-help t
              completions-format mct-completions-format)
        (let ((hook 'minibuffer-setup-hook))
          (add-hook hook #'mct--setup-completions)
          (add-hook hook #'mct--minibuffer-local-completion-map)
          (add-hook hook #'mct--minibuffer-local-filename-completion-map)
          (add-hook hook #'mct--setup-shadow-files))
        (let ((hook 'completion-list-mode-hook))
          (add-hook hook #'mct--setup-completions-styles)
          (add-hook hook #'mct--completion-list-mode-map)
          (add-hook hook #'mct--truncate-lines-silently)
          (add-hook hook #'mct--hl-line)
          (add-hook hook #'mct--display-line-numbers)
          (add-hook hook #'cursor-sensor-mode))
        (add-hook 'completion-setup-hook #'mct--clean-completions)
        (dolist (fn '(exit-minibuffer
                      choose-completion
                      minibuffer-force-complete
                      minibuffer-complete-and-exit
                      minibuffer-force-complete-and-exit))
          (advice-add fn :around #'mct--messageless))
        (advice-add #'completing-read-multiple :filter-args #'mct--crm-indicator)
        (advice-add #'minibuffer-message :around #'mct--honor-inhibit-message)
        (advice-add #'minibuf-eldef-setup-minibuffer :around #'mct--stealthily))
    (setq resize-mini-windows mct--resize-mini-windows
          completion-show-help mct--completion-show-help
          completion-auto-help mct--completion-auto-help
          completions-format mct--completions-format)
    (let ((hook 'minibuffer-setup-hook))
      (remove-hook hook #'mct--setup-completions)
      (remove-hook hook #'mct--minibuffer-local-completion-map)
      (remove-hook hook #'mct--minibuffer-local-filename-completion-map))
    (let ((hook 'completion-list-mode-hook))
      (remove-hook hook #'mct--setup-completions-styles)
      (remove-hook hook #'mct--completion-list-mode-map)
      (remove-hook hook #'mct--truncate-lines-silently)
      (remove-hook hook #'mct--hl-line)
      (remove-hook hook #'mct--display-line-numbers)
      (remove-hook hook #'cursor-sensor-mode))
    (remove-hook 'completion-setup-hook #'mct--clean-completions)
    (dolist (fn '(exit-minibuffer
                  choose-completion
                  minibuffer-force-complete
                  minibuffer-complete-and-exit
                  minibuffer-force-complete-and-exit))
      (advice-remove fn #'mct--messageless))
    (advice-remove #'completing-read-multiple #'mct--crm-indicator)
    (advice-remove #'minibuffer-message #'mct--honor-inhibit-message)
    (advice-remove #'minibuf-eldef-setup-minibuffer #'mct--stealthily)))

(provide 'mct)
;;; mct.el ends here