#lang racket/base

(provide zmq_msg_init zmq_msg_init_size zmq_msg_init_data cvoid cnull
         zmq_msg_size zmq_msg_data zmq_msg_send zmq_msg_recv zmq_msg_close
         zmq_msg_copy zmq_msg_move init-msg size->msg bytes->msg)

(require ffi/unsafe
         racket/port
         zmq/unsafe/ctypes
         zmq/unsafe/define)

(define-zmq-check zmq_msg_init _msg-pointer)
(define-zmq-check zmq_msg_init_size _msg-pointer _size)

(define-zmq-check zmq_msg_init_data
  _msg-pointer _pointer _size (_fun _pointer _pointer -> _void) _pointer)

(define-zmq zmq_msg_size (_fun _msg-pointer -> _size))

(define-zmq zmq_msg_data
  (_fun (msg : _msg-pointer)
        -> (buf : _pointer)
        -> (make-sized-byte-string buf (zmq_msg_size msg))))

(define-zmq-check zmq_msg_send _msg-pointer _socket _send_flags)
(define-zmq-check zmq_msg_recv _msg-pointer _socket _recv_flags)
(define-zmq-check zmq_msg_close _msg-pointer)
(define-zmq-check zmq_msg_copy _msg-pointer _msg-pointer)
(define-zmq-check zmq_msg_move _msg-pointer _msg-pointer)

(define (alloc-msg mode)
  (let ([msg (malloc _msg mode)])
    (set-cpointer-tag! msg msg-tag)
    msg))

(define (init-msg mode)
  (let ([msg (alloc-msg mode)])
    (zmq_msg_init msg)
    msg))

(define (size->msg mode size)
  (let ([msg (alloc-msg mode)])
    (zmq_msg_init_size msg size)
    msg))

(define (bytes->msg mode buf)
  (let* ([len (bytes-length buf)]
         [msg (size->msg mode len)])
    (memcpy (zmq_msg_data msg) buf len)
    msg))

(module+ test
  (require rackunit
           zmq/unsafe/context
           zmq/unsafe/socket)

  (let ([M1 (alloc-msg 'atomic)]
        [M2 (alloc-msg 'atomic)]
        [M3 (alloc-msg 'atomic)])
    (check = (zmq_msg_init M1) 0)
    (check = (zmq_msg_init_size M2 512) 0)
    (check = (zmq_msg_init_data M3 #"abc" 3 cvoid cnull) 0)
    (check = (zmq_msg_size M1) 0)
    (check = (zmq_msg_size M2) 512)
    (check = (zmq_msg_size M3) 3)
    (check-equal? (zmq_msg_data M3) #"abc")
    (check = (zmq_msg_close M1) 0)
    (check = (zmq_msg_close M2) 0)
    (check = (zmq_msg_close M3) 0))

  (let ([M5 (alloc-msg 'atomic)]
        [M6 (alloc-msg 'atomic)]
        [M7 (alloc-msg 'atomic)])
    (check = (zmq_msg_init_data M5 #"567vut" 6 cvoid cnull) 0)
    (check = (zmq_msg_init M6) 0)
    (check = (zmq_msg_init M7) 0)
    (check = (zmq_msg_copy M6 M5) 0)
    (check-equal? (zmq_msg_data M6) (zmq_msg_data M5))
    (check-equal? (zmq_msg_data M6) #"567vut")
    (check = (zmq_msg_move M7 M6) 0)
    (check-equal? (zmq_msg_data M7) (zmq_msg_data M5))
    (check-equal? (zmq_msg_data M7) #"567vut")
    (check = (zmq_msg_close M5) 0)
    (check = (zmq_msg_close M6) 0)
    (check = (zmq_msg_close M7) 0))

  (let* ([C (zmq_ctx_new)]
         [P (zmq_socket C 'REP)]
         [Q (zmq_socket C 'REQ)]
         [M1 (alloc-msg 'raw)]
         [M2 (alloc-msg 'atomic)])
    (check = (zmq_bind P #"inproc://msg-test") 0)
    (check = (zmq_connect Q #"inproc://msg-test") 0)
    (check = (zmq_msg_init_size M1 3) 0)
    (memcpy (zmq_msg_data M1) #"987" 3)
    (check = (zmq_msg_init M2) 0)
    (check = (zmq_msg_send M1 Q null) 3)
    (check = (zmq_msg_recv M2 P null) 3)
    (check-equal? (zmq_msg_data M2) #"987"))

  (let* ([C (zmq_ctx_new)]
         [P (zmq_socket C 'REP)]
         [Q (zmq_socket C 'REQ)]
         [M1 (alloc-msg 'atomic)]
         [M2 (alloc-msg 'raw)])
    (check = (zmq_msg_init M1) 0)
    (check = (zmq_msg_init_size M2 10) 0)
    (check = (zmq_msg_size M1) 0)
    (check = (zmq_msg_size M2) 10)
    (check = (zmq_bind P #"inproc://test2") 0)
    (check = (zmq_connect Q #"inproc://test2") 0)
    (let ([buf (zmq_msg_data M2)])
      (bytes-fill! buf 0)
      (bytes-copy! buf 0 #"987zyx")
      (check = (zmq_msg_send M2 Q null) 10)
      (check = (zmq_msg_recv M1 P null) 10)
      (check = (zmq_msg_size M1) 10)
      (check-equal? (zmq_msg_data M1) #"987zyx\0\0\0\0")
      (check-equal? (zmq_msg_data M2) #""))
    (check = (zmq_msg_close M1) 0)
    (check = (zmq_msg_close M2) 0))

  (let* ([C (zmq_ctx_new)]
         [P (zmq_socket C 'REP)]
         [Q (zmq_socket C 'REQ)]
         [M3 (alloc-msg 'atomic)]
         [M4 (alloc-msg 'atomic)])
    (check = (zmq_msg_init_data M3 #"654mon" 6 cvoid cnull) 0)
    (check = (zmq_msg_init M4) 0)
    (check = (zmq_msg_size M3) 6)
    (check = (zmq_msg_size M4) 0)
    (check = (zmq_bind P #"inproc://test2") 0)
    (check = (zmq_connect Q #"inproc://test2") 0)
    (check = (zmq_send_const Q #"ok" 2 null) 2)
    (let ([buf (make-bytes 5)])
      (bytes-fill! buf 0)
      (check = (zmq_recv P buf 5 null) 2)
      (check-equal? buf #"ok\0\0\0"))
    (check = (zmq_msg_close M3) 0)
    (check = (zmq_msg_close M4) 0)))
