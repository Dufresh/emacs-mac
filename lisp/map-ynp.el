;;; map-ynp.el --- General-purpose boolean question-asker.

;;; Copyright (C) 1991, 1992 Free Software Foundation, Inc.

;; Author: Roland McGrath <roland@gnu.ai.mit.edu>
;; Keywords: lisp, extensions

;;; This program is free software; you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 2, or (at your option)
;;; any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; A copy of the GNU General Public License can be obtained from this
;;; program's author (send electronic mail to roland@ai.mit.edu) or from
;;; the Free Software Foundation, Inc., 675 Mass Ave, Cambridge, MA
;;; 02139, USA.

;;; Commentary:

;;; map-y-or-n-p is a general-purpose question-asking function.
;;; It asks a series of y/n questions (a la y-or-n-p), and decides to
;;; applies an action to each element of a list based on the answer.
;;; The nice thing is that you also get some other possible answers
;;; to use, reminiscent of query-replace: ! to answer y to all remaining
;;; questions; ESC or q to answer n to all remaining questions; . to answer
;;; y once and then n for the remainder; and you can get help with C-h.

;;; Code:

;;;###autoload
(defun map-y-or-n-p (prompter actor list &optional help action-alist)
  "Ask a series of boolean questions.
Takes args PROMPTER ACTOR LIST, and optional args HELP and ACTION-ALIST.

LIST is a list of objects, or a function of no arguments to return the next
object or nil.

If PROMPTER is a string, the prompt is \(format PROMPTER OBJECT\).  If not
a string, PROMPTER is a function of one arg (an object from LIST), which
returns a string to be used as the prompt for that object.  If the return
value is not a string, it is eval'd to get the answer; it may be nil to
ignore the object, t to act on the object without asking the user, or a
form to do a more complex prompt.

ACTOR is a function of one arg (an object from LIST),
which gets called with each object that the user answers `yes' for.

If HELP is given, it is a list (OBJECT OBJECTS ACTION),
where OBJECT is a string giving the singular noun for an elt of LIST;
OBJECTS is the plural noun for elts of LIST, and ACTION is a transitive
verb describing ACTOR.  The default is \(\"object\" \"objects\" \"act on\"\).

At the prompts, the user may enter y, Y, or SPC to act on that object;
n, N, or DEL to skip that object; ! to act on all following objects;
ESC or q to exit (skip all following objects); . (period) to act on the
current object and then exit; or \\[help-command] to get help.

If ACTION-ALIST is given, it is an alist (KEY FUNCTION HELP) of extra keys
that will be accepted.  KEY is a character; FUNCTION is a function of one
arg (an object from LIST); HELP is a string.  When the user hits KEY,
FUNCTION is called.  If it returns non-nil, the object is considered
\"acted upon\", and the next object from LIST is processed.  If it returns
nil, the prompt is repeated for the same object.

Returns the number of actions taken."
  (let* ((old-help-form help-form)
	 (help-form (let ((object (if help (nth 0 help) "object"))
			  (objects (if help (nth 1 help) "objects"))
			  (action (if help (nth 2 help) "act on")))
		      (concat (format "Type SPC or `y' to %s the current %s;
DEL or `n' to skip the current %s;
! to %s all remaining %s;
ESC or `q' to exit;\n"
				      action object object action objects)
			      (mapconcat (function
					  (lambda (elt)
					    (format "%c to %s"
						    (nth 0 elt)
						    (nth 2 elt))))
					 action-alist
					 ";\n")
			      (if action-alist ";\n")
			      (format "or . (period) to %s \
the current %s and exit."
				      action object))))
	 (user-keys (if action-alist
			(concat (mapconcat (function
					    (lambda (elt)
					      (key-description
					       (char-to-string (car elt)))))
					   action-alist ", ")
				" ")
		      ""))
	 (actions 0)
	 prompt char elt tail
	 (next (if (or (symbolp list)
		       (subrp list)
		       (byte-code-function-p list)
		       (and (consp list)
			    (eq (car list) 'lambda)))
		   (function (lambda ()
			       (setq elt (funcall list))))
		 (function (lambda ()
			     (if list
				 (progn
				   (setq elt (car list)
					 list (cdr list))
				   t)
			       nil))))))
    (if (stringp prompter)
	(setq prompter (` (lambda (object)
			    (format (, prompter) object)))))
    (while (funcall next)
      (setq prompt (funcall prompter elt))
      (if (stringp prompt)
	  (progn
	    ;; Prompt the user about this object.
	    (let ((cursor-in-echo-area t))
	      (message "%s(y, n, !, ., q, %sor %s) "
		       prompt user-keys
		       (key-description (char-to-string help-char)))
	      (setq char (read-char)))
	    (cond ((or (= ?q char)
		       (= ?\e char))
		   (setq next (function (lambda () nil))))
		  ((or (= ?y char)
		       (= ?Y char)
		       (= ?  char))
		   ;; Act on the object.
		   (let ((help-form old-help-form))
		     (funcall actor elt))
		   (setq actions (1+ actions)))
		  ((or (= ?n char)
		       (= ?N char)
		       (= ?\^? char))
		   ;; Skip the object.
		   )
		  ((= ?. char)
		   ;; Act on the object and then exit.
		   (funcall actor elt)
		   (setq actions (1+ actions)
			 next (function (lambda () nil))))
		  ((= ?! char)
		   ;; Act on this and all following objects.
		   (if (eval (funcall prompter elt))
		       (progn
			 (funcall actor elt)
			 (setq actions (1+ actions))))
		   (while (funcall next)
		     (if (eval (funcall prompter elt))
			 (progn
			   (funcall actor elt)
			   (setq actions (1+ actions))))))
		  ((= ?? char)
		   (setq unread-command-events (list help-char))
		   (setq next (` (lambda ()
				   (setq next '(, next))
				   '(, elt)))))
		  ((setq tail (assq char action-alist))
		   ;; A user-defined key.
		   (if (funcall (nth 1 tail) elt) ;Call its function.
		       ;; The function has eaten this object.
		       (setq actions (1+ actions))
		     ;; Regurgitated; try again.
		     (setq next (` (lambda ()
				   (setq next '(, next))
				   '(, elt))))))
		  (t
		   ;; Random char.
		   (message "Type %s for help."
			    (key-description (char-to-string help-char)))
		   (beep)
		   (sit-for 1)
		   (setq next (` (lambda ()
				   (setq next '(, next))
				   '(, elt)))))))
	(if (eval prompt)
	    (progn
	      (funcall actor elt)
	      (setq actions (1+ actions))))))
    ;; Clear the last prompt from the minibuffer.
    (message "")
    ;; Return the number of actions that were taken.
    actions))

;;; map-ynp.el ends here
