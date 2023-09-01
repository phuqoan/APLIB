;;
;; aPLib compression library  -  the smaller the better :)
;;
;; Code by PhuQoan - 2021.

d_1280  = 1280
d_32000 = 32000
d_16800 = 16800h

vstk    struc
aP_input dd ?                           ; ... ; input stream
aP_output dd ?                          ; ... ; output stream
aP_tagcount dd ?                        ; ... ; count for load new empty tagbyte
aP_tagbyte dd ?                         ; ... ; GAMMA here
aP_hashtable dd ?                       ; ... ; point to wmem size=16800*4
aP_nexthashentry dd ?
aP_hashptr dd ?
aP_hash_base dd ?
org_input_1 dd ?
aP_R0   dd ?                            ; ... ; previous distance
aP_f_R0 dd ?                            ; ...
aP_lookup dd 256 dup(?)                 ; ... ; 256 pointers contiguous
vstk    ends


s_LZ    struc
_length dd ?
_distance dd ?
s_LZ    ends

        .686p
        .model flat

_text   segment para public 'CODE' use32

; =============== S U B R O U T I N E =======================================

; append bit value 0

push_Gamma_0 proc near
        dec     [ebp+vstk.aP_tagcount]
        jnz     short @@_1
        mov     [ebp+vstk.aP_tagcount], 8 ; 8 bits per byte
        mov     eax, [ebp+vstk.aP_output] ; output stream
        mov     [ebp+vstk.aP_tagbyte], eax
        shl     byte ptr [eax], 1
        inc     [ebp+vstk.aP_output]    ; output stream
        retn
@@_1:
        mov     eax, [ebp+vstk.aP_tagbyte]
        shl     byte ptr [eax], 1
        retn
push_Gamma_0 endp

; =============== S U B R O U T I N E =======================================

; append bit value 1

push_Gamma_1 proc near
        stc
push_Gamma_1 endp

; =============== S U B R O U T I N E =======================================

; append bit is Carry_Flag

push_Gamma_CF proc near
        dec     [ebp+vstk.aP_tagcount]
        jnz     short @@_2		; attention! This doesn't affect Carry_Flag
        mov     [ebp+vstk.aP_tagcount],8  ; 8 bits per byte
        mov     eax, [ebp+vstk.aP_output] ; output stream
        mov     [ebp+vstk.aP_tagbyte], eax ; GAMMA here
        rcl     byte ptr [eax], 1
        inc     [ebp+vstk.aP_output]    ; output stream
        retn
@@_2:                                  
        mov     eax, [ebp+vstk.aP_tagbyte] ; GAMMA here
        rcl     byte ptr [eax], 1
        retn
push_Gamma_CF endp

; =============== S U B R O U T I N E =======================================

; eax gamma for output
; gamma first in first out

aP_outputGAMMA proc near
        xor     ecx, ecx

_og_rotateGamma:
        shr     eax, 1
        rcl     edx, 1                  ; rotate bit for first in first out
        inc     ecx                     ; count of bit
        cmp     eax, 1
        ja      short _og_rotateGamma

@@_5:
        shr     edx, 1
        call    push_Gamma_CF           ; append bit is Carry_Flag
        dec     ecx
        jz      short @@_6
        call    push_Gamma_1            ; next block send gamma_1
        jmp     short @@_5

@@_6:                                  ; append bit value 0
        call    push_Gamma_0
        retn
aP_outputGAMMA endp

; =============== S U B R O U T I N E =======================================

; eax=index, edx=dist, ecx=leng
; ret eax

aP_getLITERALlength proc near
        push    ebx
        push    esi
        push    edi
        mov     edi, eax
        mov     eax, 15                 ; max distance is 15
        cmp     edx, eax
        cmova   edx, eax
        mov     esi, edx
        xor     eax, eax                ; reset count

_gl_mainloop:                           ; load char at index
        mov     bl, [edi]
        test    bl, bl
        jz      short @@_8
        mov     edx, edi
        sub     edx, esi                ; edx=index-distance
        push    esi

_gl_scanchar:
        cmp     [edx], bl
        jz      short @@_7
        inc     edx
        dec     esi                     ; dec distance
        jnz     short _gl_scanchar
        add     eax, 2

@@_7:
        pop     esi
@@_8:
        add     eax, 7
        inc     edi                     ; next index
        loop    _gl_mainloop            ; load char at index

        pop     edi
        pop     esi
        pop     ebx
        retn
aP_getLITERALlength endp

; =============== S U B R O U T I N E =======================================

; eax=index, edx=distance

aP_outputLITERAL proc near
        mov     [ebp+vstk.aP_f_R0], 0
        mov     ecx, edx
        mov     dl, [eax]               ; load char
        test    dl, dl                  ; ???in case zero, WTF
        jz      short _ol_store_distance ; send 7 bits

        mov     edx, ecx                ; edx=distance
        mov     ecx, 15
        cmp     edx, ecx
        cmova   edx, ecx                ; edx=max(15)

        mov     cl, [eax]
        sub     eax, edx                ; index-=distance

_ol_scanchar:                           ; scan char
        cmp     [eax], cl
        jz      short _ol_chk_dist      ; found char
        inc     eax                     ; next index
        dec     edx                     ; decrease distance
        jnz     short _ol_scanchar      ; scan char

_ol_store_LIT:                          ; distance==0
        call    push_Gamma_0
        mov     eax, [ebp+vstk.aP_output] ; output stream
        mov     [eax], cl               ; save literal
        inc     [ebp+vstk.aP_output]    ; output stream

        retn

_ol_chk_dist:
        test    edx, edx
        jz      short _ol_store_LIT     ; distance==0

_ol_store_distance:
        mov     ecx, 7                  ; send 7 bits
        or      dl, 1110000b            ; 3gamma_1 + 4bits_dl
        shl     dl, 1                   ; remove 1 hi_bit

@@_9:
        shl     dl, 1                   ; store hi bit first
        call    push_Gamma_CF           ; append bit is Carry_Flag
        loop    @@_9

        retn
aP_outputLITERAL endp

; =============== S U B R O U T I N E =======================================

; eax=distance, edx=length
; ret eax

aP_getCODEPAIRlength proc near
        cmp     eax, [ebp+vstk.aP_R0]   ; previous distance
        jz      @@_19                   ; zero count
        cmp     eax, 128
        jnb     short @@_11
        cmp     edx, 4
        jnb     short @@_10
        neg     eax
        sbb     eax, eax                ; eax=0 or eax=-1
        and     eax, 6                  ; eax=0 or eax=6
        add     eax, 5
        retn

@@_10:
        sub     edx, 2
        jmp     short @@_13

@@_11:
        cmp     eax, d_1280
        jb      short @@_13
        dec     edx
        cmp     eax, d_32000
        jb      short @@_13
        dec     edx

@@_13:
        shr     eax, 8

@@_14:
        add     eax, 3

        push    edx                     ; save edx
        mov     edx, eax
        xor     eax, eax                ; zero count
        cmp     edx, 2
        jge     short @@_16
        add     eax, 100
        jmp     short @@_17

_gc_loop_1:
        add     eax, 2

@@_16:
        shr     edx, 1
        jnz     short _gc_loop_1

@@_17:
        pop     edx                     ; load edx

        cmp     edx, 2
        jge     short @@_18

        add     eax, 110
        retn

_gc_loop_2:                             ; count of bit
        add     eax, 2
@@_18:
        shr     edx, 1
        jnz     short _gc_loop_2        ; count of bit

        add     eax, 10
        retn

@@_19:
        xor     eax, eax                ; zero count
        cmp     edx, 2
        jge     short @@_20

        add     eax, 104
        retn

_gc_loop_3:
        add     eax, 2
@@_20:
        shr     edx, 1
        jnz     short _gc_loop_3

        add     eax, 4
        retn
aP_getCODEPAIRlength endp

; =============== S U B R O U T I N E =======================================

; eax=distance, edx=length

aP_outputCODEPAIR proc near
        push    ebx
        mov     ebx, eax
        cmp     [ebp+vstk.aP_f_R0], 0
        jz      _flagdistance_zero
        cmp     ebx, 128
        jnb     short _f1_G1_G0_GG_8B   ; (f_distance==1) and (dist>=128 or len>=4)
        cmp     edx, 4
        jb      _G1_G1_G0_8B            ; dist<128; leng<4

_f1_G1_G0_GG_8B:                        ; (f_distance==1) and (dist>=128 or len>=4)
        call    push_Gamma_1
        call    push_Gamma_0            ; append bit value 0
        mov     eax, ebx
        shr     eax, 8                  ; remove 8 bits
        add     eax, 2
        push    edx                     ; save edx
        call    aP_outputGAMMA          ; eax gamma for output
                                        ; gamma first in first out
        pop     edx                     ; load edx

        mov     eax, [ebp+vstk.aP_output] ; output stream
        mov     [eax], bl               ; store 8 bits
        inc     [ebp+vstk.aP_output]    ; output stream

        mov     [ebp+vstk.aP_R0], ebx   ; save distance for
                                        ; reuse on next codepair
        cmp     ebx, 128
        jnb     short @@_21
        sub     edx, 2
        jmp     _cp_push_GLeng

@@_21:
        cmp     ebx, d_1280
        jb      short @@_22
        dec     edx
        cmp     ebx, d_32000
        jb      short @@_22
        dec     edx
@@_22:
        jmp     _cp_push_GLeng

_flagdistance_zero:
        mov     [ebp+vstk.aP_f_R0], 1

        cmp     ebx, 128
        jnb     short _out_G1_G0
        cmp     edx, 4
        jnb     short _out_G1_G0
        cmp     ebx, [ebp+vstk.aP_R0]   ; previous distance
        jz      short _out_G1_G0

_G1_G1_G0_8B:                           ; dist<128; leng<4
        call    push_Gamma_1
        call    push_Gamma_1            ; append bit value 1
        call    push_Gamma_0            ; append bit value 0
        mov     al, bl
        shr     dl, 1                   ; shift out bit0 of length
        rcl     al, 1                   ; append to bit0 of distance
        mov     edx, [ebp+vstk.aP_output] ; output stream
        mov     [edx], al               ; output 1 byte
        inc     [ebp+vstk.aP_output]    ; output stream

        mov     [ebp+vstk.aP_R0], ebx   ; save distance for
                                        ; reuse on next codepair
        jmp     _cp_ret

_out_G1_G0:                             ; append bit value 1
        call    push_Gamma_1
        call    push_Gamma_0            ; append bit value 0
        cmp     ebx, [ebp+vstk.aP_R0]   ; previous distance
        jz      short _G0_G0_Gleng
        mov     eax, ebx
        shr     eax, 8                  ; remove 8 bits(lo)
        add     eax, 3                  ; 11b
        push    edx                     ; save edx
        call    aP_outputGAMMA          ; eax gamma for output
                                        ; gamma first in first out
        pop     edx                     ; load edx

        mov     eax, [ebp+vstk.aP_output] ; output stream
        mov     [eax], bl               ; store 8 bits
        inc     [ebp+vstk.aP_output]    ; output stream

        mov     [ebp+vstk.aP_R0], ebx   ; save distance for
                                        ; reuse on next codepair
        cmp     ebx, 128
        jnb     short @@_23
        sub     edx, 2
        jmp     short _cp_push_GLeng

@@_23:
        cmp     ebx, d_1280
        jb      short _cp_push_GLeng
        dec     edx
        cmp     ebx, d_32000
        jb      short _cp_push_GLeng
        dec     edx
        jmp     short _cp_push_GLeng

_G0_G0_Gleng:                           ; append bit value 0
        call    push_Gamma_0
        call    push_Gamma_0            ; append bit value 0

_cp_push_GLeng:
        mov     eax, edx
        call    aP_outputGAMMA          ; eax gamma for output
                                        ; gamma first in first out
_cp_ret:
        pop     ebx
        retn
aP_outputCODEPAIR endp

; =============== S U B R O U T I N E =======================================

; arg_0, index, idx_left, idx_right
; return arg_0 struc s_LZ

aP_findmatch proc near

var_litleng= dword ptr -0Ch
var_litdist= dword ptr -8
var_count_loop= dword ptr -4

a_ret_struc= dword ptr  4
a_fm_index= dword ptr  8
a_d_left= dword ptr  0Ch
a_d_right= dword ptr  10h

        sub     esp, 0Ch
        push    ebx
        push    esi
        push    edi
        
        mov     esi, [esp+18h+a_fm_index]

_hash_linker:
        mov     ecx, [ebp+vstk.aP_hashptr]
        cmp     ecx, esi                ; test hashptr reaching index
        jnb     _fm_chk_left_right
        mov     eax, [ebp+vstk.aP_nexthashentry]
        lea     edx, [eax+d_16800]
        cmp     eax, edx
        jnb     short _fm_resethashentry ; eax>=(eax+d_16800)
        sub     eax, [ebp+vstk.aP_hash_base]
        jg      short _fm_load_hashptr  ; eax>0
        add     eax, d_16800
        jmp     short _fm_load_hashptr

_fm_resethashentry:                     ; eax>=(eax+d_16800)
        xor     eax, eax

_fm_load_hashptr:
        movzx   edx, byte ptr [ecx]
        movzx   ecx, byte ptr [ecx+1]   ; load 2 chars from hashptr
        mov     edi, [ebp+edx*4+vstk.aP_lookup] ; 256 pointers contiguous
        mov     ebx, [edi+ecx*4]
        mov     edx, [ebp+vstk.aP_hashtable] ; point to wmem size=16800*4
        mov     [edx+eax*4], ebx        ; link list
        mov     eax, [ebp+vstk.aP_nexthashentry]
        mov     [edi+ecx*4], eax        ; link list

        inc     eax
        mov     [ebp+vstk.aP_nexthashentry], eax ; nexthashentry++
        inc     [ebp+vstk.aP_hashptr]   ; hashptr++
        mov     ecx, eax                ; if (nexthashentry-hashbase)>d_16800
                                        ; {hashbase=nexhashentry-1}
        sub     ecx, [ebp+vstk.aP_hash_base]
        cmp     ecx, d_16800
        jbe     short @@_25
        dec     eax
        mov     [ebp+vstk.aP_hash_base], eax

@@_25:
        jmp     _hash_linker

_fm_chk_left_right:
        xor     ebx, ebx
        mov     [esp+18h+var_litleng], ebx
        mov     [esp+18h+var_litdist], ebx ; zero return value
                                        ; ;
        mov     eax, [esp+18h+a_d_right]
        cmp     eax, 1                  ; idx_right<=1 reaching the end
        jbe     _fm_ret_LIT
        mov     edx, (d_16800-100h)     ; max_idx_right=16700h
        cmp     eax, edx
        jbe     short @@_26
        mov     [esp+18h+a_d_right], edx

@@_26:
        cmp     [esp+18h+a_d_left], edx
        jbe     short @@_27            ; load index_content
        mov     [esp+18h+a_d_left], edx

@@_27:                                 ; load index_content
        movzx   eax, byte ptr [esi]
        movzx   ecx, byte ptr [esi+1]
        mov     eax, [ebp+eax*4+vstk.aP_lookup] ; 256 pointers contiguous
        mov     edi, [eax+ecx*4]        ; edi=hash_index
        mov     ecx, [ebp+vstk.org_input_1]

_fm_loop_hash:
        test    edi, edi
        jz      _fm_ret_LIT             ; hash index zero then return
        lea     eax, [edi+ecx]
        cmp     eax, esi                ; reaching index
        jb      short @@_30             ; break loop

        lea     eax, [edi+d_16800]
        cmp     eax, [ebp+vstk.aP_nexthashentry]
        jbe     short @@_28            ; (edi+d_16800)<=nexthashentry
        sub     edi, [ebp+vstk.aP_hash_base]
        jg      short @@_29            ; edi>0
        add     edi, d_16800
        jmp     short @@_29

@@_28:                                 ; (edi+d_16800)<=nexthashentry
        xor     edi, edi

@@_29:                                 ; point to wmem size=16800*4
        mov     eax, [ebp+vstk.aP_hashtable]
        mov     edi, [eax+edi*4]        ; edi=hash_value
        jmp     short _fm_loop_hash

@@_30:
        mov     [esp+18h+var_count_loop], 2048

_fm_mainloop:
        test    edi, edi
        jz      _fm_ret_LIT             ; hash index zero then return
        mov     ecx, esi
        sub     ecx, eax                ; distance=index-hash_found
        cmp     ecx, [esp+18h+a_d_left] ; chk distance>idx_left
        ja      _fm_ret_LIT

        mov     ebx, [esp+18h+var_litleng]
        mov     dl, [ebx+eax]
        cmp     dl, [ebx+esi]
        mov     ebx, 2                  ; set length=2
        jz      short @@_31

        cmp     ecx, [ebp+vstk.aP_R0]   ; current distance == previous distance
        jnz     _fm_load_nexthash

@@_31:
        mov     edx, [esp+18h+a_d_right]
        cmp     ebx, edx
        jnb     short @@_34             ; crazy jump

        push    edi                     ; lack of register, save edi
        push    esi
        lea     edi, [esi+2]
        neg     esi
        add     esi, eax                ; lea esi, [eax-esi]

@@_32:                                  ; scan for repeat char
        mov     al, [edi+esi]
        cmp     al, [edi]
        jnz     short @@_33
        inc     ebx                     ; inc length
        inc     edi                     ; next index
        cmp     ebx, edx
        jb      short @@_32             ; scan for repeat char

@@_33:
        pop     esi
        pop     edi                     ; reload edi

        cmp     ebx, edx
@@_34:                                  ; crazy jump
        jz      _fm_ret_ebx_ecx

        cmp     ebx, [esp+18h+var_litleng]
        jbe     short @@_35

        push    edi                     ; lack of register, save edi
        mov     edx, ebx
        mov     eax, ecx
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        mov     edi, eax
        mov     edx, [esp+18h+4+var_litleng] ; esp+04
        mov     eax, [esp+18h+4+var_litdist] ; esp+04
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        neg     eax
        add     eax, edi                ; lea eax,[edi-eax]
        add     eax, eax
        cdq
        mov     edi, 13                 ; idiv 6.5
        idiv    edi
        pop     edi                     ; reload edi
        add     eax, [esp+18h+var_litleng]

        cmp     ebx, eax
        jbe     short _fm_load_nexthash

        jmp     short _fm_update_retval

@@_35:                                 ; previous distance
        cmp     ecx, [ebp+vstk.aP_R0]
        jnz     short _fm_load_nexthash

        push    edi                     ; lack of register, save edi
        mov     edx, ebx
        mov     eax, ecx
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        mov     edi, eax
        mov     edx, [esp+18h+4+var_litleng] ; esp+04
        mov     eax, [esp+18h+4+var_litdist] ; esp+04
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        sub     eax, edi
        cdq
        mov     edi, 6                  ; idiv 6.0
        idiv    edi
        pop     edi                     ; reload edi
        add     eax, ebx

        cmp     eax, [esp+18h+var_litleng]
        jb      short _fm_load_nexthash

_fm_update_retval:
        mov     [esp+18h+var_litleng], ebx
        mov     [esp+18h+var_litdist], ecx

_fm_load_nexthash:
        lea     eax, [edi+d_16800]
        cmp     eax, [ebp+vstk.aP_nexthashentry]
        jbe     short @@_36
        sub     edi, [ebp+vstk.aP_hash_base]
        jg      short @@_37            ; edi>0
        add     edi, d_16800
        jmp     short @@_37

@@_36:
        xor     edi, edi

@@_37:                                 ; point to wmem size=16800*4
        mov     eax, [ebp+vstk.aP_hashtable]
        mov     edi, [eax+edi*4]        ; ;
                                        ; ;
        mov     eax, [ebp+vstk.org_input_1]
        add     eax, edi

; check for loop
        dec     [esp+18h+var_count_loop]
        jnz     _fm_mainloop

_fm_ret_LIT:
        mov     ebx, [esp+18h+var_litleng]
        mov     ecx, [esp+18h+var_litdist]

_fm_ret_ebx_ecx:
        mov     eax, [esp+18h+a_ret_struc]
        mov     [eax+s_LZ._length], ebx
        mov     [eax+s_LZ._distance], ecx

        pop     edi
        pop     esi
        pop     ebx
        add     esp, 0Ch
        retn    10h
aP_findmatch endp

; =============== S U B R O U T I N E =======================================

        public _aP_workmem_size
_aP_workmem_size proc near
        mov     eax, 0A0000h
        retn
_aP_workmem_size endp


; =============== S U B R O U T I N E =======================================


        public _aP_max_packed_size
_aP_max_packed_size proc near
        mov     eax, [esp+4]
        mov     edx, eax
        shr     edx, 3
        lea     eax, [eax+edx+64]       ; arg_0+(arg_0/8)+64
        retn
_aP_max_packed_size endp


; =============== S U B R O U T I N E =======================================

; LZStruc1, LZStruc2, flag, mode
; ret eax 0 or 1

chk_div_codepair proc near

a_1st_LZ= dword ptr  4
a_2nd_LZ= dword ptr  8
a_flag  = dword ptr  0Ch
a_mode  = dword ptr  10h

        push    ebx
        push    esi
        push    ebp
        push    edi

        mov     eax, [esp+10h+a_1st_LZ]
        mov     esi, [eax+s_LZ._length]
        mov     edi, [eax+s_LZ._distance]
        mov     edx, esi                ; esi use late
        mov     eax, edi                ; edi use late
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        mov     ecx, [esp+10h+a_2nd_LZ]
        mov     edx, [ecx+s_LZ._length]
        push    edx                     ; pop ebx late
        push    eax                     ; pop ebp late
        mov     eax, [ecx+s_LZ._distance]
        mov     ebx, eax                ; ebx use late
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        pop     ebp                     ; push eax
        push    eax                     ; pop edi late

        neg     eax
        add     eax, ebp                ; lea eax,[ebp-eax]
        mov     ecx, 9                  ; idiv 4.5
        cmp     [esp+18h+a_mode], 0     ; esp+08
        jz      short @@_38
        mov     cl, 11                  ; idiv 5.5
        xchg    edi, ebx                ; swap register for compare
@@_38:
        cmp     edi, ebx
        pop     edi                     ; push eax
        pop     ebx                     ; push edx
        jl      short @@_39
        mov     cl, 8                   ; idiv 4.0
@@_39:
        add     eax, eax
        cdq
        idiv    ecx
        add     eax, ebx

        xor     ecx, ecx                ; ret 0
        cmp     eax, esi
        jle     short @@_40
        mov     cl, 1                   ; ret 1

@@_40:
        cmp     [esp+10h+a_flag], 0
        jbe     short @@_41
        cmp     ebx, esi
        jl      short @@_41
        mov     eax, 1                  ; ret 1
        cmp     edi, ebp
        jl      short @@_42

@@_41:
        mov     eax, ecx

@@_42:
        pop     edi
        pop     ebp
        pop     esi
        pop     ebx
        retn    10h
chk_div_codepair endp

; =============== S U B R O U T I N E =======================================

; eax=(struc stack_variable)

The_Packer proc near

var_f_CodePair= dword ptr -30h
v_count_loop= dword ptr -2Ch
var_idx1= dword ptr -28h
var_tmplen= dword ptr -24h
var_idx0_len= dword ptr -20h            ; 1st block
var_idx0_dist= dword ptr -1Ch
var_idx3_len= dword ptr -18h            ; 4th block
var_idx3_dist= dword ptr -14h
var_idx2_len= dword ptr -10h            ; 3rd block
var_idx2_dist= dword ptr -0Ch
var_idx1_len= dword ptr -8              ; 2nd block
var_idx1_dist= dword ptr -4

_p_src  = dword ptr  4                  ; source stream
_p_dst  = dword ptr  8                  ; destination
_p_len  = dword ptr  0Ch                ; length of source
_p_wmem = dword ptr  10h                ; working memory area
_p_cb   = dword ptr  14h                ; user call back routine
_p_cbp  = dword ptr  18h                ; callback parameter

        sub     esp, 30h
        push    ebp
        mov     ebp, eax                ; ebp point to static variable
        cmp     [esp+34h+_p_len], 0     ; length of source
        jnz     short @@_43

        xor     eax, eax
_p_out:
        pop     ebp
        add     esp, 30h
        retn    18h

@@_43:                                 ; source stream
        mov     ecx, [esp+34h+_p_src]
        test    ecx, ecx                ; test src
        jnz     short @@_44

_p_ret_ffffffff:
        or      eax, 0FFFFFFFFh
        jmp     short _p_out

@@_44:                                 ; destination
        mov     edx, [esp+34h+_p_dst]
        test    edx, edx
        jz      short _p_ret_ffffffff
        mov     eax, [esp+34h+_p_wmem]  ; working memory area
        test    eax, eax
        jz      short _p_ret_ffffffff
        push    esi                     ; esi = nothing
                                        ; ecx = src
                                        ; edx = dst
                                        ; eax = wmem
                                        ; ebp = var
        push    edi
        push    ebx
        mov     [ebp+vstk.aP_input], ecx ; input stream
        dec     ecx
        mov     [ebp+vstk.org_input_1], ecx
        mov     [ebp+vstk.aP_output], edx ; output stream
        mov     [ebp+vstk.aP_hashtable], eax ; point to wmem size=16800*4
        xor     esi, esi
        mov     [eax], esi              ; set hashtable zero
        mov     edi, 256                ; loop 256 buffers
        lea     edx, [eax+(d_16800*4)+18h]
        lea     ecx, [ebp+vstk.aP_lookup] ; apppend 256pointers to buffer 1024 bytes zero

_p_init_hash:
        mov     [ecx], edx
        xor     eax, eax

_p_clearhash:                           ; clear hash
        mov     [edx+eax], esi
        add     eax, 4
        cmp     eax, 1024
        jb      short _p_clearhash      ; clear hash
        add     ecx, 4                  ; next pointer
        add     edx, 1024
        dec     edi
        jnz     short _p_init_hash

        inc     esi                     ; esi=1
        or      eax, 0FFFFFFFFh
        mov     [ebp+vstk.aP_R0], eax   ; -1
        mov     [ebp+vstk.aP_hash_base], edi ; 0
        mov     [ebp+vstk.aP_nexthashentry], esi ; 1

        mov     ecx, [ebp+vstk.aP_input] ; input stream
        mov     [ebp+vstk.aP_hashptr], ecx ; hashptr first point to input_stream
        mov     cl, [ecx]

        mov     edx, [ebp+vstk.aP_output] ; output stream
        mov     [edx], cl               ; tranfer 1st char from source
        inc     [ebp+vstk.aP_output]    ; next output
        inc     [ebp+vstk.aP_input]     ; next input

        mov     [ebp+vstk.aP_f_R0], edi ; 0
        mov     [ebp+vstk.aP_tagcount], esi ; setup tagbyte
                                        ; ;
        mov     [esp+40h+var_idx1], eax ; -1
        mov     [esp+40h+_p_wmem], edi  ; after this use as static temp var
        mov     [esp+40h+v_count_loop], edi ; 0
                                        ; ;
        mov     eax, [esp+40h+_p_len]   ; length of source
        dec     eax
        cmp     eax, esi                ; check (len-1)<=1
        jbe     _p_end_of_source

_p_mainloop:                            ; esi=idx_left
        mov     ecx, [esp+40h+_p_cb]
        test    ecx, ecx                ; test callback
        jz      short _p_chk_idx1
        mov     eax, [esp+40h+v_count_loop]
        inc     eax
        mov     [esp+40h+v_count_loop], eax
        test    eax, 1FFFh              ; frequency callback
        jnz     short _p_chk_idx1       ; ;
                                        ; ;
        mov     edx, [esp+40h+_p_cbp]   ; callback parameter
        mov     eax, [ebp+vstk.aP_output] ; output stream
        sub     eax, [esp+40h+_p_dst]   ; destination
        push    edx
        mov     edx, [ebp+vstk.aP_input] ; input stream
        sub     edx, [esp+44h+_p_src]   ; source stream
        push    eax
        mov     eax, [esp+48h+_p_len]   ; length of source
        push    edx
        push    eax
        call    ecx                     ; call back user routine
                                        ; plz backup regs
        add     esp, 10h
        test    eax, eax                ; callback return 0 then break
        jz      _p_user_break

_p_chk_idx1:
        cmp     esi, [esp+40h+var_idx1]
        jnz     short _fm_index_0       ; same index, speed up
                                        ; load previous findmatch result
        mov     ecx, [esp+40h+var_idx1_len] ; 2nd block
        mov     edx, [esp+40h+var_idx1_dist]
        mov     [esp+40h+var_idx0_len], ecx ; 1st block
        mov     [esp+40h+var_idx0_dist], edx
        jmp     short _p_chk_idx0len

_fm_index_0:                            ; input stream
        mov     eax, [ebp+vstk.aP_input]
        lea     ecx, [esp+40h+var_idx0_len] ; hold return value
        mov     edx, [esp+40h+_p_len]   ; length of source
        sub     edx, esi
        push    edx
        push    esi                     ; idx_left
        push    eax                     ; input stream
        push    ecx
        call    aP_findmatch            ; arg_0, index, idx_left, idx_right
                                        ; return arg_0 struc s_LZ

_p_chk_idx0len:                         ; 1st block
        cmp     [esp+40h+var_idx0_len], 2
        jl      @@_64                  ; idx0_leng < 2
        mov     eax, [ebp+vstk.aP_R0]   ; previous distance
        cmp     [esp+40h+var_idx0_dist], eax
        jnz     short _fm_index_1
        cmp     edi, 1
        jbe     _p_check_length
        mov     ebx, [esp+40h+var_idx3_dist]
        cmp     ebx, eax
        jz      _p_check_length
        mov     eax, [esp+40h+_p_wmem]  ; working memory area
        mov     edx, esi
        sub     edx, edi
        mov     ecx, edi
        call    aP_getLITERALlength     ; eax=index, edx=dist, ecx=leng
                                        ; ret eax
        mov     [esp+40h+var_tmplen], eax
        mov     edx, edi
        mov     eax, ebx
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        cmp     eax, [esp+40h+var_tmplen]
        jge     _p_check_length
        mov     eax, ebx
        cmp     eax, d_1280
        jl      short @@_45
        cmp     edi, 2
        jz      _p_check_length

@@_45:
        cmp     eax, d_32000
        jl      short _fm_index_1
        cmp     edi, 3
        jz      _p_check_length

_fm_index_1:                            ; length of source
        mov     ebx, [esp+40h+_p_len]
        sub     ebx, esi                ; esi=idx_left
                                        ; ebx=idx_right
        mov     [esp+40h+var_tmplen], ebx ; ;
                                        ; ;
        mov     eax, [ebp+vstk.aP_input] ; input stream
        inc     eax                     ; next 1 step
        lea     ecx, [esp+40h+var_idx1_len] ; 2nd block
        lea     edx, [ebx-1]            ; decrease right
        push    edx
        lea     edx, [esi+1]            ; increase left
        mov     [esp+44h+var_idx1], edx ; reuse findmatch result
        push    edx
        push    eax
        push    ecx
        call    aP_findmatch            ; arg_0, index, idx_left, idx_right
                                        ; return arg_0 struc s_LZ
        lea     eax, [esp+40h+var_idx0_len] ; 1st block
        lea     edx, [esp+40h+var_idx1_len] ; 2nd block
        push    0                       ; mode 0
        push    edi
        push    edx
        push    eax
        call    chk_div_codepair        ; LZStruc1, LZStruc2, flag, mode
                                        ; ret eax 0 or 1
        mov     [esp+40h+var_f_CodePair], eax
        test    edi, edi
        jnz     short @@_46            ; ;
                                        ; ;
        mov     ecx, [esp+40h+var_idx0_len] ; 1st block
        cmp     [esp+40h+var_idx1_len], ecx ; 2nd block
        jge     short @@_46            ; ;
                                        ; ;LZ4_Len<LZ1_len
        mov     edx, [esp+40h+var_idx1_len] ; 2nd block
        mov     eax, [esp+40h+var_idx1_dist]
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        mov     ebx, eax                ; ebx use late
                                        ; ;
        mov     eax, [ebp+vstk.aP_input] ; input stream
        mov     edx, esi
        mov     ecx, 1
        call    aP_getLITERALlength     ; eax=index, edx=dist, ecx=leng
                                        ; ret eax
        lea     ebx, [eax+ebx+1]        ; ;
                                        ; ;
        mov     edx, [esp+40h+var_idx0_len] ; 1st block
        mov     eax, [esp+40h+var_idx0_dist]
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        cmp     ebx, eax
        mov     ebx, [esp+40h+var_tmplen]
        jg      short _fm_index_2

@@_46:
        cmp     [esp+40h+var_f_CodePair], 0
        jnz     @@_62

_fm_index_2:                            ; 1st block
        cmp     [esp+40h+var_idx0_len], 2
        jle     short _p_check_length   ; ;
                                        ; ;
        mov     eax, [ebp+vstk.aP_input] ; input stream
        add     eax, 2                  ; next 2 steps
        lea     ecx, [esp+40h+var_idx2_len] ; 3rd block
        lea     edx, [ebx-2]            ; decrease right
        push    edx
        lea     edx, [esi+2]            ; increase left
        push    edx
        push    eax
        push    ecx
        call    aP_findmatch            ; arg_0, index, idx_left, idx_right
                                        ; return arg_0 struc s_LZ
        lea     eax, [esp+40h+var_idx0_len] ; 1st block
        lea     edx, [esp+40h+var_idx2_len] ; 3rd block
        push    1                       ; mode 1
        push    edi
        push    edx
        push    eax
        call    chk_div_codepair        ; LZStruc1, LZStruc2, flag, mode
                                        ; ret eax 0 or 1
        test    eax, eax
        jnz     @@_62                  ; ;
                                        ; ;
        cmp     [esp+40h+var_idx0_len], 3 ; 1st block
        jle     short _p_check_length   ; ;
                                        ; ;
        mov     eax, [ebp+vstk.aP_input] ; input stream
        add     eax, 3                  ; next 3 steps
        lea     ecx, [esp+40h+var_idx2_len] ; 3rd block
        lea     ebx, [ebx-3]            ; decrease right
        lea     edx, [esi+3]            ; increase left
        push    ebx
        push    edx
        push    eax
        push    ecx
        call    aP_findmatch            ; arg_0, index, idx_left, idx_right
                                        ; return arg_0 struc s_LZ
        lea     eax, [esp+40h+var_idx0_len] ; 1st block
        lea     edx, [esp+40h+var_idx2_len] ; 3rd block
        push    1                       ; mode 1
        push    edi
        push    edx
        push    eax
        call    chk_div_codepair        ; LZStruc1, LZStruc2, flag, mode
                                        ; ret eax 0 or 1
        test    eax, eax
        jnz     @@_62

_p_check_length:
        test    edi, edi
        jz      _p_zerolength           ; edi==0
        cmp     edi, 1
        jbe     @@_53                  ; edi==1
        mov     eax, [esp+40h+_p_len]   ; length of source
        sub     eax, esi
        add     eax, edi
        cmp     eax, edi
        cmova   eax, edi

        mov     edx, [esp+40h+_p_wmem]  ; working memory area
        lea     ecx, [esp+40h+var_idx2_len] ; 3rd block
        mov     ebx, esi
        sub     ebx, edi
        mov     [esp+40h+var_f_CodePair], ebx
        push    eax
        push    ebx
        push    edx
        push    ecx
        call    aP_findmatch            ; arg_0, index, idx_left, idx_right
                                        ; return arg_0 struc s_LZ
        cmp     [esp+40h+var_idx2_len], edi ; 3rd block
        jb      short @@_47            ; ;
                                        ; ;
        mov     eax, [esp+40h+var_idx2_dist]
        mov     edx, edi
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        mov     ebx, eax                ; ;
                                        ; ;
        mov     eax, [esp+40h+var_idx3_dist]
        mov     edx, edi
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        cmp     eax, ebx
        mov     ebx, [esp+40h+var_f_CodePair]
        jle     short @@_47
        mov     ecx, [esp+40h+var_idx2_len] ; 3rd block
        mov     eax, [esp+40h+var_idx2_dist]
        mov     [esp+40h+var_idx3_len], ecx ; 4th block
        mov     [esp+40h+var_idx3_dist], eax

@@_47:                                 ; working memory area
        mov     eax, [esp+40h+_p_wmem]
        mov     edx, ebx
        mov     ecx, edi
        call    aP_getLITERALlength     ; eax=index, edx=dist, ecx=leng
                                        ; ret eax
        mov     [esp+40h+var_tmplen], eax ; ;
                                        ; ;
        mov     eax, [esp+40h+var_idx3_dist]
        mov     edx, edi
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        mov     ebx, eax
        cmp     ebx, [esp+40h+var_tmplen]
        jge     short _p_1_outlit       ; edi==2 or edi==3
        mov     ecx, [esp+40h+var_idx0_dist]
        cmp     ecx, [ebp+vstk.aP_R0]   ; previous distance
        jnz     short @@_48
        mov     edx, [esp+40h+var_idx0_len] ; 1st block
        lea     eax, [ecx+1]
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        add     eax, ebx
        mov     [esp+40h+var_f_CodePair], eax
        mov     edx, [esp+40h+var_idx0_len] ; 1st block
        mov     eax, [esp+40h+var_idx0_dist]
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        add     eax, [esp+40h+var_tmplen]
        cmp     eax, [esp+40h+var_f_CodePair]
        jle     short _p_1_outlit       ; edi==2 or edi==3

@@_48:
        mov     eax, [esp+40h+var_idx3_dist]
        cmp     eax, [ebp+vstk.aP_R0]   ; previous distance
        jnz     short @@_49
        cmp     [ebp+vstk.aP_f_R0], 0
        jz      short @@_51

@@_49:
        cmp     eax, d_1280
        jl      short @@_50
        cmp     edi, 2
        jz      short _p_1_outlit       ; edi==2 or edi==3

@@_50:
        cmp     eax, d_32000
        jl      short @@_51
        cmp     edi, 3
        jz      short _p_1_outlit       ; edi==2 or edi==3

@@_51:
        mov     edx, edi
        call    aP_outputCODEPAIR       ; eax=distance, edx=length
        jmp     short @@_54

_p_1_outlit:                            ; edi==2 or edi==3
        mov     ebx, [esp+40h+_p_wmem]

@@_52:
        mov     eax, ebx
        mov     edx, esi
        sub     edx, edi
        call    aP_outputLITERAL        ; eax=index, edx=distance
        inc     ebx                     ; next index
        dec     edi
        jnz     short @@_52            ; ;
                                        ; ;
        mov     [esp+40h+_p_wmem], ebx  ; working memory area
        jmp     short _p_zerolength     ; edi==0

@@_53:                                 ; edi==1
        mov     eax, [esp+40h+_p_wmem]
        lea     edx, [esi-1]
        call    aP_outputLITERAL        ; eax=index, edx=distance

@@_54:
        xor     edi, edi

_p_zerolength:                          ; edi==0
        mov     ebx, [esp+40h+var_idx0_len]
        cmp     ebx, 3
        jg      @@_60
        mov     eax, [ebp+vstk.aP_input] ; input stream
        mov     edx, esi
        mov     ecx, ebx
        call    aP_getLITERALlength     ; eax=index, edx=dist, ecx=leng
                                        ; ret eax
        mov     [esp+40h+var_tmplen], eax ; ;
                                        ; ;
        mov     eax, [esp+40h+var_idx0_dist]
        mov     edx, ebx
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        cmp     eax, [esp+40h+var_tmplen]
        jg      short @@_57
        mov     eax, [esp+40h+var_idx0_dist]
        cmp     eax, [ebp+vstk.aP_R0]   ; previous distance
        jnz     short @@_55
        cmp     [ebp+vstk.aP_f_R0], 0
        jz      short @@_61

@@_55:
        cmp     eax, d_1280
        jl      short @@_56
        cmp     ebx, 2
        jz      short @@_57

@@_56:
        cmp     eax, d_32000
        jl      short @@_61

@@_57:
        mov     [esp+40h+var_f_CodePair], ebx
        test    ebx, ebx
        jz      short @@_59            ; add esi, ebx-1

@@_58:                                 ; input stream
        mov     eax, [ebp+vstk.aP_input]
        mov     edx, esi
        call    aP_outputLITERAL        ; eax=index, edx=distance
        inc     [ebp+vstk.aP_input]     ; input stream
        dec     [esp+40h+var_f_CodePair]
        jnz     short @@_58

@@_59:                                 ; add esi, ebx-1
        lea     esi, [esi+ebx-1]
        jmp     short @@_66

@@_60:
        mov     eax, [esp+40h+var_idx0_dist]

@@_61:
        mov     edx, ebx
        call    aP_outputCODEPAIR       ; eax=distance, edx=length
        add     [ebp+vstk.aP_input], ebx ; !!!next input size ebx
        jmp     short @@_59            ; add esi, ebx-1

@@_62:
        test    edi, edi
        jnz     short @@_63
        mov     eax, [esp+40h+var_idx0_len] ; 1st block
        mov     ecx, [esp+40h+var_idx0_dist]
        mov     edx, [ebp+vstk.aP_input] ; input stream
        mov     [esp+40h+var_idx3_len], eax ; 4th block
        mov     [esp+40h+var_idx3_dist], ecx
        mov     [esp+40h+_p_wmem], edx  ; working memory area

@@_63:
        inc     edi
        jmp     short @@_65            ; next input

@@_64:                                 ; idx0_leng < 2
        test    edi, edi
        jnz     short @@_63
        mov     eax, [ebp+vstk.aP_input] ; store literal
        mov     edx, esi
        call    aP_outputLITERAL        ; eax=index, edx=distance

@@_65:                                 ; next input
        inc     [ebp+vstk.aP_input]

@@_66:
        test    edi, edi
        jz      _p_mainloop_chk
        cmp     edi, [esp+40h+var_idx3_len] ; 4th block
        jnz     _p_mainloop_chk         ; ;
                                        ; ;
        mov     eax, [esp+40h+_p_len]   ; length of source
        sub     eax, esi
        add     eax, edi
        cmp     eax, edi
        cmova   eax, edi

        mov     edx, [esp+40h+_p_wmem]  ; working memory area
        lea     ecx, [esp+40h+var_idx2_len] ; 3rd block
        mov     ebx, esi
        sub     ebx, edi
        mov     [esp+40h+var_f_CodePair], ebx
        push    eax
        push    ebx
        push    edx
        push    ecx
        call    aP_findmatch            ; arg_0, index, idx_left, idx_right
                                        ; return arg_0 struc s_LZ
        cmp     [esp+40h+var_idx2_len], edi ; 3rd block
        jb      short @@_67
        mov     eax, [esp+40h+var_idx2_dist]
        mov     edx, edi
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        mov     ebx, eax                ; ;
                                        ; ;
        mov     eax, [esp+40h+var_idx3_dist]
        mov     edx, edi
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        cmp     eax, ebx
        mov     ebx, [esp+40h+var_f_CodePair]
        jle     short @@_67
        mov     ecx, [esp+40h+var_idx2_dist]
        mov     edx, [esp+40h+var_idx2_len] ; 3rd block
        mov     [esp+40h+var_idx3_dist], ecx
        mov     [esp+40h+var_idx3_len], edx ; 4th block

@@_67:                                 ; working memory area
        mov     eax, [esp+40h+_p_wmem]
        mov     edx, ebx
        mov     ecx, edi
        call    aP_getLITERALlength     ; eax=index, edx=dist, ecx=leng
                                        ; ret eax
        mov     ebx, eax                ; ;
                                        ; ;
        mov     eax, [esp+40h+var_idx3_dist]
        mov     edx, edi
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        cmp     eax, ebx
        jge     short @@_71            ; edi==2 or edi==3
        mov     eax, [esp+40h+var_idx3_dist]
        cmp     eax, [ebp+vstk.aP_R0]   ; previous distance
        jnz     short @@_68
        cmp     [ebp+vstk.aP_f_R0], 0
        jz      short @@_70

@@_68:
        cmp     eax, d_1280
        jl      short @@_69
        cmp     edi, 2
        jz      short @@_71            ; edi==2 or edi==3

@@_69:
        cmp     eax, d_32000
        jl      short @@_70
        cmp     edi, 3
        jz      short @@_71            ; edi==2 or edi==3

@@_70:
        mov     edx, edi
        call    aP_outputCODEPAIR       ; eax=distance, edx=length
        xor     edi, edi
        jmp     short _p_mainloop_chk

@@_71:                                 ; edi==2 or edi==3
        mov     ebx, [esp+40h+_p_wmem]

_p_loop2_outlit:
        mov     eax, ebx
        mov     edx, esi
        sub     edx, edi
        call    aP_outputLITERAL        ; eax=index, edx=distance
        inc     ebx
        dec     edi
        jnz     short _p_loop2_outlit   ; ;
                                        ; ;
        mov     [esp+40h+_p_wmem], ebx  ; working memory area

_p_mainloop_chk:
        inc     esi
        mov     eax, [esp+40h+_p_len]   ; length of source
        dec     eax
        cmp     esi, eax
        jb      _p_mainloop             ; (idx_left+1)<(len-1)
                                        ; ;

        test    edi, edi
        jz      _p_end_of_source
        cmp     edi, 1
        jbe     @@_76                  ; edi<=1
        mov     eax, [esp+40h+_p_wmem]  ; working memory area
        mov     edx, esi
        sub     edx, edi
        mov     ecx, edi
        call    aP_getLITERALlength     ; eax=index, edx=dist, ecx=leng
                                        ; ret eax
        mov     ebx, eax
        mov     eax, [esp+40h+var_idx3_dist]
        mov     edx, edi
        call    aP_getCODEPAIRlength    ; eax=distance, edx=length
                                        ; ret eax
        cmp     eax, ebx                ; CodePairlength vs LITlength
        jg      short @@_75            ; ;
                                        ; ;
        mov     eax, [esp+40h+var_idx3_dist]
        cmp     eax, [ebp+vstk.aP_R0]   ; previous distance
        jnz     short @@_72
        cmp     [ebp+vstk.aP_f_R0], 0
        jz      short @@_74

@@_72:
        cmp     eax, d_1280
        jl      short @@_73
        cmp     edi, 2
        jz      short @@_75

@@_73:
        cmp     eax, d_32000
        jl      short @@_74
        cmp     edi, 3
        jz      short @@_75

@@_74:
        mov     edx, edi
        call    aP_outputCODEPAIR       ; eax=distance, edx=length
        jmp     short _p_end_of_source

@@_75:                                 ; working memory area
        mov     ebx, [esp+40h+_p_wmem]

_p_loop3_outlit:
        mov     eax, ebx
        mov     edx, esi                ; idx_left
        sub     edx, edi
        call    aP_outputLITERAL        ; eax=index, edx=distance
        inc     ebx
        dec     edi
        jnz     short _p_loop3_outlit   ; ;
                                        ; ;
        jmp     short _p_end_of_source

@@_76:                                 ; edi<=1
        mov     eax, [esp+40h+_p_wmem]
        lea     edx, [esi-1]
        call    aP_outputLITERAL        ; eax=index, edx=distance

_p_end_of_source:                       ; length of source
        mov     edi, [esp+40h+_p_len]
        cmp     esi, edi
        jnb     short _p_ending_Gamma   ; idx_left>=len

_p_ending_LIT:                          ; input stream
        mov     eax, [ebp+vstk.aP_input]
        mov     edx, esi
        call    aP_outputLITERAL        ; eax=index, edx=distance
        inc     [ebp+vstk.aP_input]     ; input stream
        inc     esi
        cmp     esi, edi
        jb      short _p_ending_LIT

_p_ending_Gamma:                        ; append bit value 1
        call    push_Gamma_1
        call    push_Gamma_1            ; append bit value 1
        call    push_Gamma_0            ; append bit value 0

        mov     ecx, [ebp+vstk.aP_tagcount] ; move top of struc for speed
        dec     ecx                     ; flushing remaining GAMMA
        mov     eax, [ebp+vstk.aP_tagbyte] ; GAMMA here
        shl     byte ptr [eax], cl      ; shift bit for depack
                                        ; ;
        mov     eax, [ebp+vstk.aP_output] ; output stream
        mov     [eax], ch               ; output zero end
        inc     [ebp+vstk.aP_output]    ; output stream

        mov     eax, [esp+40h+_p_cb]    ; user call back routine
        test    eax, eax
        jz      short _p_ret_szpack     ; return packed size
        mov     ecx, [esp+40h+_p_cbp]   ; callback parameter
        mov     edx, [ebp+vstk.aP_output] ; output stream
        sub     edx, [esp+40h+_p_dst]   ; destination
        push    ecx
        mov     ecx, [ebp+vstk.aP_input] ; input stream
        sub     ecx, [esp+44h+_p_src]   ; source stream
        push    edx
        push    ecx
        push    edi                     ; src length
        call    eax                     ; call back user routine
        add     esp, 10h                ; ;
                                        ; ;
        test    eax, eax
        jnz     short _p_ret_szpack     ; return packed size
        mov     eax, esi                ; return idx_left
        jmp     short _p_end

_p_user_break:
        or      eax, 0FFFFFFFFh
        jmp     short _p_end

_p_ret_szpack:                          ; return packed size
        mov     eax, [ebp+vstk.aP_output]
        sub     eax, [esp+40h+_p_dst]   ; destination

_p_end:
        pop     ebx
        pop     edi
        pop     esi
        pop     ebp
        add     esp, 30h
        retn    18h
The_Packer endp


; =============== S U B R O U T I N E =======================================


        public _aP_pack
_aP_pack proc near

_src    = dword ptr  4
_dst    = dword ptr  8
_len    = dword ptr  0Ch
_wmem   = dword ptr  10h
_cb_    = dword ptr  14h
_cbp    = dword ptr  18h

        mov     eax, [esp+_len]
        sub     esp, size vstk
        mov     ecx, [esp+(size vstk)+_cbp]
        mov     edx, [esp+(size vstk)+_cb_]
        push    ecx
        mov     ecx, [esp+(size vstk)+4+_wmem]
        push    edx
        mov     edx, [esp+(size vstk)+8+_dst]
        push    ecx
        push    eax
        mov     eax, [esp+(size vstk)+16+_src]
        push    edx
        push    eax
        lea     eax, [esp+(6*4)]        ; leave room for 6 args
                                        ; internal struc vstk
        call    The_Packer              ; eax=(struc stack_variable)
        add     esp, size vstk
        retn
_aP_pack endp


_text   ends

        end
