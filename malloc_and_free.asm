; BSD 3-Clause License
; 
; Copyright (c) 2019, k4m1
; All rights reserved.
; 
; Redistribution and use in source and binary forms, with or without
; modification, are permitted provided that the following conditions are met:
; 
; * Redistributions of source code must retain the above copyright notice, this
;   list of conditions and the following disclaimer.
; 
; * Redistributions in binary form must reproduce the above copyright notice,
;   this list of conditions and the following disclaimer in the documentation
;   and/or other materials provided with the distribution.
; 
; * Neither the name of the copyright holder nor the names of its
;   contributors may be used to endorse or promote products derived from
;   this software without specific prior written permission.
; 
; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
; DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
; FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
; SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
; CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
; OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
; OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

bits 16

;
; we use following header to see how much memory is
; allocated to where:
;
; MALLOC_SIGNATURE_IN_USE: 'used'
; MALLOC_SIGNATURE_FREE: 'free'
; SIZE: xx xx
; 

%ifndef __MLIB_ASM__
%define __MLIB_ASM__

%define __mlib_addr_free 'free'
%define __mlib_addr_used 'used'
%define __mlib_base_addr 0xC000
%define __mlib_max_offset 0x3000
%define __mlib_max_addr (__mlib_base_addr + __mlib_max_offset)

; This function initializes 12 kilobytes of RAM for us to use
init_ram:
	mov	cx, __mlib_max_offset
	mov	bx, 0
	.clear:
		mov	byte [__mlib_base_addr + bx], 0
		inc	bx
		loop	.clear
	ret

; Malloc() takes memory size at SI.
; Returns address to free memory at DI, or
; DI = 0 on error
malloc:
	push	bx
	xor	bx, bx
	add	bx, __mlib_base_addr
	.find_addr:
		; see if current offset to memory is okay or not
		cmp	dword [bx], 0
		je	.found_free_memory
		cmp	dword [bx], __mlib_addr_free
		jne	.get_next_addr
		; Ok, so memory has been used, but has now been marked as free
		add	bx, 4
		; Check how much free memory there is
		; if there isn't, get next address
		cmp	si, word [bx]
		jge	.found_free_memory
		add	bx, word [bx]
		jmp	.find_addr
	.get_next_addr:
		add	bx, 4
		add	bx, word [bx]
		add	bx, 2
		jmp	.find_addr
	.found_free_memory:
		; Check that there's enough space at our free
		; slot to allocate
		add	bx, 6
		cmp	bx, __mlib_max_addr
		jge	.out_of_memory
		; Ok, there is enough space, mark this memory area used
		sub	bx, 6
		mov	dword [bx], __mlib_addr_used
		add	bx, 4
		mov	word [bx], si
		add	bx, 2
		; Return pointer to free memory
	.ret:
		mov	di, bx
		pop	bx
		ret
	.out_of_memory:
		; We don't have quite enough space
		; return 0
		xor	bx, bx
		jmp	.ret

; Free() takes one argument, which is pointer to memory
; to free at DI.
free:
	push	bp
	mov	bp, sp
	; --- do not double free
	sub	di, 6
	cmp	dword [di], __mlib_addr_used
	jne	.double_free
	; mark current address free
	mov	dword [di], __mlib_addr_free
	; try to make memory as continugous as possible
	call	clean_mem
	.ret:
		mov	sp, bp
		pop	bp
		ret
	.double_free:
		mov	si, .msg_double_free
		call	print
		jmp	.ret
.msg_double_free:
	db "Free(): double free!", 0x0D, 0x0A, 0

; clean_mem() does not require arguments, it's purpose is to
; prevent RAM memory fragmentation
clean_mem:
	pusha
	mov	di, __mlib_base_addr ; Start of our memory region
	xor	bx, bx	; Size of current memory chunk

	.start_of_clean_memory:
		cmp	dword [di], 0
		je	.done

		cmp	dword [di], __mlib_addr_used
		je	.get_to_next_chunk

		cmp	dword [di], __mlib_addr_free
		je	.chunk_is_free_check_next

		mov	si, .msg_clean_mem_err
		call	print
		jmp	.done

		; End of loop one

	; If address is in use, move to next chunk
	.get_to_next_chunk:
		mov	bx, word [di+4]
		add	di, bx
		add	di, 6
		jmp	.start_of_clean_memory

	; If chunk is free, check next one
	.chunk_is_free_check_next:
		mov	bx, word [di+4]
		add	di, bx
		add	di, 6
		; check if next is used, if so, move to next one
		cmp	dword [di], __mlib_addr_used
		je	.get_to_next_chunk

		; Check if we're at last chunk or not
		cmp	dword [di], 0
		je	.end_of_touched_memory

		; Ok, so next chunk is free, merge with this
		mov	cx, word [di+4]
		mov	dword [di], 0
		mov	word [di+4], 0
		sub	di, bx
		sub	di, 6
		add	word [di+4], cx
		jmp	.chunk_is_free_check_next

		; End of loop

	.end_of_touched_memory:
		sub	di, bx
		sub	di, 6
		mov	dword [di], 0
		mov	word [di+4], 0

	.done:
		popa
		ret
.msg_clean_mem_err:
	db "Free(): Memory fragmentation error", 0x0A, 0x0D, 0

%endif

