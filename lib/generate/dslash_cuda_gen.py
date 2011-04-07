import sys

### complex numbers ########################################################################

def complexify(a):
    return [complex(x) for x in a]

def complexToStr(c):
    def fltToString(a):
        if a == int(a): return `int(a)`
        else: return `a`
    
    def imToString(a):
        if a == 0: return "0i"
        elif a == -1: return "-i"
        elif a == 1: return "i"
        else: return fltToString(a)+"i"
    
    re = c.real
    im = c.imag
    if re == 0 and im == 0: return "0"
    elif re == 0: return imToString(im)
    elif im == 0: return fltToString(re)
    else:
        im_str = "-"+imToString(-im) if im < 0 else "+"+imToString(im)
        return fltToString(re)+im_str


### projector matrices ########################################################################

id = complexify([
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1
])

gamma1 = complexify([
    0,  0, 0, 1j,
    0,  0, 1j, 0,
    0, -1j, 0, 0,
    -1j,  0, 0, 0
])

gamma2 = complexify([
    0, 0, 0, 1,
    0, 0, -1,  0,
    0, -1, 0,  0,
    1, 0, 0,  0
])

gamma3 = complexify([
    0, 0, 1j,  0,
    0, 0, 0, -1j,
    -1j, 0, 0,  0,
    0, 1j, 0,  0
])

gamma4 = complexify([
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, -1, 0,
    0, 0, 0, -1
])

igamma5 = complexify([
    0, 0, 1j, 0,
    0, 0, 0, 1j,
    1j, 0, 0, 0,
    0, 1j, 0, 0
])


def gplus(g1, g2):
    return [x+y for (x,y) in zip(g1,g2)]

def gminus(g1, g2):
    return [x-y for (x,y) in zip(g1,g2)]

def projectorToStr(p):
    out = ""
    for i in range(0, 4):
        for j in range(0,4):
            out += complexToStr(p[4*i+j]) + " "
        out += "\n"
    return out

projectors = [
    gminus(id,gamma1), gplus(id,gamma1),
    gminus(id,gamma2), gplus(id,gamma2),
    gminus(id,gamma3), gplus(id,gamma3),
    gminus(id,gamma4), gplus(id,gamma4),
]

### code generation  ########################################################################

def indent(code):
    return ''.join(["    "+line+"\n" for line in code.splitlines()])

def block(code):
    return "{\n"+indent(code)+"}"

def sign(x):
    if x==1: return "+"
    elif x==-1: return "-"
    elif x==+2: return "+2*"
    elif x==-2: return "-2*"

def nthFloat4(n):
    return `(n/4)` + "." + ["x", "y", "z", "w"][n%4]

def nthFloat2(n):
    return `(n/2)` + "." + ["x", "y"][n%2]


def in_re(s, c): return "i"+`s`+`c`+"_re"
def in_im(s, c): return "i"+`s`+`c`+"_im"
def g_re(d, m, n): return ("g" if (d%2==0) else "gT")+`m`+`n`+"_re"
def g_im(d, m, n): return ("g" if (d%2==0) else "gT")+`m`+`n`+"_im"
def out_re(s, c): return "o"+`s`+`c`+"_re"
def out_im(s, c): return "o"+`s`+`c`+"_im"
def h1_re(h, c): return ["a","b"][h]+`c`+"_re"
def h1_im(h, c): return ["a","b"][h]+`c`+"_im"
def h2_re(h, c): return ["A","B"][h]+`c`+"_re"
def h2_im(h, c): return ["A","B"][h]+`c`+"_im"
def c_re(b, sm, cm, sn, cn): return "c"+`(sm+2*b)`+`cm`+"_"+`(sn+2*b)`+`cn`+"_re"
def c_im(b, sm, cm, sn, cn): return "c"+`(sm+2*b)`+`cm`+"_"+`(sn+2*b)`+`cn`+"_im"
def a_re(b, s, c): return "a"+`(s+2*b)`+`c`+"_re"
def a_im(b, s, c): return "a"+`(s+2*b)`+`c`+"_im"

def tmp_re(s, c): return "tmp"+`s`+`c`+"_re"
def tmp_im(s, c): return "tmp"+`s`+`c`+"_im"


def def_input_spinor():
    str = []
    str.append("// input spinor\n")
    str.append("#ifdef SPINOR_DOUBLE\n")
    str.append("#define spinorFloat double\n")
    for s in range(0,4):
        for c in range(0,3):
            i = 3*s+c
            str.append("#define "+in_re(s,c)+" I"+nthFloat2(2*i+0)+"\n")
            str.append("#define "+in_im(s,c)+" I"+nthFloat2(2*i+1)+"\n")
    str.append("\n")
    str.append("#else\n")
    str.append("#define spinorFloat float\n")
    for s in range(0,4):
        for c in range(0,3):
            i = 3*s+c
            str.append("#define "+in_re(s,c)+" I"+nthFloat4(2*i+0)+"\n")
            str.append("#define "+in_im(s,c)+" I"+nthFloat4(2*i+1)+"\n")
    str.append("#endif // SPINOR_DOUBLE\n\n")
    return ''.join(str)
# end def def_input_spinor


def def_gauge():
    str = []
    str.append("// gauge link\n")
    str.append("#ifdef GAUGE_FLOAT2\n")
    for m in range(0,3):
        for n in range(0,3):
            i = 3*m+n
            str.append("#define "+g_re(0,m,n)+" G"+nthFloat2(2*i+0)+"\n")
            str.append("#define "+g_im(0,m,n)+" G"+nthFloat2(2*i+1)+"\n")

    str.append("// temporaries\n")
    str.append("#define A_re G"+nthFloat2(18)+"\n")
    str.append("#define A_im G"+nthFloat2(19)+"\n")    
    str.append("\n")
    str.append("#else\n")
    for m in range(0,3):
        for n in range(0,3):
            i = 3*m+n
            str.append("#define "+g_re(0,m,n)+" G"+nthFloat4(2*i+0)+"\n")
            str.append("#define "+g_im(0,m,n)+" G"+nthFloat4(2*i+1)+"\n")

    str.append("// temporaries\n")
    str.append("#define A_re G"+nthFloat4(18)+"\n")
    str.append("#define A_im G"+nthFloat4(19)+"\n")    
    str.append("\n")
    str.append("#endif // GAUGE_DOUBLE\n\n")    
            
    str.append("// conjugated gauge link\n")
    for m in range(0,3):
        for n in range(0,3):
            i = 3*m+n
            str.append("#define "+g_re(1,m,n)+" (+"+g_re(0,n,m)+")\n")
            str.append("#define "+g_im(1,m,n)+" (-"+g_im(0,n,m)+")\n")
    str.append("\n")

    return ''.join(str)
# end def def_gauge


def def_clover():
    str = []
    str.append("// first chiral block of inverted clover term\n")
    str.append("#ifdef CLOVER_DOUBLE\n")
    i = 0
    for m in range(0,6):
        s = m/3
        c = m%3
        str.append("#define "+c_re(0,s,c,s,c)+" C"+nthFloat2(i)+"\n")
        i += 1
    for n in range(0,6):
        sn = n/3
        cn = n%3
        for m in range(n+1,6):
            sm = m/3
            cm = m%3
            str.append("#define "+c_re(0,sm,cm,sn,cn)+" C"+nthFloat2(i)+"\n")
            str.append("#define "+c_im(0,sm,cm,sn,cn)+" C"+nthFloat2(i+1)+"\n")
            i += 2
    str.append("#else\n")
    i = 0
    for m in range(0,6):
        s = m/3
        c = m%3
        str.append("#define "+c_re(0,s,c,s,c)+" C"+nthFloat4(i)+"\n")
        i += 1
    for n in range(0,6):
        sn = n/3
        cn = n%3
        for m in range(n+1,6):
            sm = m/3
            cm = m%3
            str.append("#define "+c_re(0,sm,cm,sn,cn)+" C"+nthFloat4(i)+"\n")
            str.append("#define "+c_im(0,sm,cm,sn,cn)+" C"+nthFloat4(i+1)+"\n")
            i += 2
    str.append("#endif // CLOVER_DOUBLE\n\n")    

    for n in range(0,6):
        sn = n/3
        cn = n%3
        for m in range(0,n):
            sm = m/3
            cm = m%3
            str.append("#define "+c_re(0,sm,cm,sn,cn)+" (+"+c_re(0,sn,cn,sm,cm)+")\n")
            str.append("#define "+c_im(0,sm,cm,sn,cn)+" (-"+c_im(0,sn,cn,sm,cm)+")\n")
    str.append("\n")

    str.append("// second chiral block of inverted clover term (reuses C0,...,C9)\n")
    for n in range(0,6):
        sn = n/3
        cn = n%3
        for m in range(0,6):
            sm = m/3
            cm = m%3
            str.append("#define "+c_re(1,sm,cm,sn,cn)+" "+c_re(0,sm,cm,sn,cn)+"\n")
            if m != n: str.append("#define "+c_im(1,sm,cm,sn,cn)+" "+c_im(0,sm,cm,sn,cn)+"\n")
    str.append("\n")

    return ''.join(str)
# end def def_clover


def def_output_spinor():
    str = []
    str.append("// output spinor\n")
    for s in range(0,4):
        for c in range(0,3):
            i = 3*s+c
            if 2*i < sharedFloats:
                str.append("#define "+out_re(s,c)+" s["+`(2*i+0)`+"*SHARED_STRIDE]\n")
            else:
                str.append("volatile spinorFloat "+out_re(s,c)+";\n")
            if 2*i+1 < sharedFloats:
                str.append("#define "+out_im(s,c)+" s["+`(2*i+1)`+"*SHARED_STRIDE]\n")
            else:
                str.append("volatile spinorFloat "+out_im(s,c)+";\n")
    str.append("\n")
    return ''.join(str)
# end def def_output_spinor


def prolog():
    str = []
    str.append("// *** CUDA DSLASH ***\n\n" if not dagger else "// *** CUDA DSLASH DAGGER ***\n\n")
    str.append("#define SHARED_FLOATS_PER_THREAD "+`sharedFloats`+"\n\n")

    str.append(def_input_spinor())
    str.append(def_gauge())    
    if clover == True: str.append(def_clover())
    str.append(def_output_spinor())

    str.append(
"""

#include "read_gauge.h"
#include "read_clover.h"
#include "io_spinor.h"

int sid = blockIdx.x*blockDim.x + threadIdx.x;
if (sid >= param.threads) return;

int X, x1, x2, x3, x4;
coordsFromIndex(X, x1, x2, x3, x4, sid, param.parity);

#ifdef MULTI_GPU
// now calculate the new x4 given the T offset and space between T slices
int x4_new = (x4 + param.tOffset) * param.tMul;
sid += Vs*(x4_new - x4); // new spatial index
X += X3X2X1*(x4_new - x4);
int x1diff = ((x2 + x3 + x4_new + param.parity) & 1) - ((x2 + x3 + x4 + param.parity) & 1);
x1 += x1diff;
X += x1diff;
x4 = x4_new;
#endif

""")
    
    if sharedFloats > 0:
        str.append("#ifdef SPINOR_DOUBLE\n")
        str.append("#if (__CUDA_ARCH__ >= 200)\n")
        str.append("#define SHARED_STRIDE 16 // to avoid bank conflicts on Fermi\n")
        str.append("#else\n")
        str.append("#define SHARED_STRIDE  8 // to avoid bank conflicts on G80 and GT200\n")
        str.append("#endif\n")
        str.append("extern __shared__ spinorFloat sd_data[];\n")
        str.append("volatile spinorFloat *s = sd_data + SHARED_FLOATS_PER_THREAD*SHARED_STRIDE*(threadIdx.x/SHARED_STRIDE)\n")
        str.append("                                  + (threadIdx.x % SHARED_STRIDE);\n")
        str.append("#else\n")
        str.append("#if (__CUDA_ARCH__ >= 200)\n")
        str.append("#define SHARED_STRIDE 32 // to avoid bank conflicts on Fermi\n")
        str.append("#else\n")
        str.append("#define SHARED_STRIDE 16 // to avoid bank conflicts on G80 and GT200\n")
        str.append("#endif\n")
        str.append("extern __shared__ spinorFloat ss_data[];\n")
        str.append("volatile spinorFloat *s = ss_data + SHARED_FLOATS_PER_THREAD*SHARED_STRIDE*(threadIdx.x/SHARED_STRIDE)\n")
        str.append("                                  + (threadIdx.x % SHARED_STRIDE);\n")
        str.append("#endif\n\n")
    
    for s in range(0,4):
        for c in range(0,3):
            str.append(out_re(s,c) + " = " + out_im(s,c)+" = 0;\n")
    str.append("\n")
    
    return ''.join(str)
# end def prolog


def gen(dir, pack_only=False):
    projIdx = dir if not dagger else dir + (1 - 2*(dir%2))
    projStr = projectorToStr(projectors[projIdx])
    def proj(i,j):
        return projectors[projIdx][4*i+j]
    
    # if row(i) = (j, c), then the i'th row of the projector can be represented
    # as a multiple of the j'th row: row(i) = c row(j)
    def row(i):
        assert i==2 or i==3
        if proj(i,0) == 0j:
            return (1, proj(i,1))
        if proj(i,1) == 0j:
            return (0, proj(i,0))
    
    str = []
    
    projName = "P"+`dir/2`+["-","+"][projIdx%2]
    str.append("// Projector "+projName+"\n")
    for l in projStr.splitlines():
        str.append("// "+l+"\n")
    str.append("\n")
    
    if dir == 0: str.append("int sp_idx = ((x1==X1m1) ? X-X1m1 : X+1) >> 1;\n")
    if dir == 1: str.append("int sp_idx = ((x1==0)    ? X+X1m1 : X-1) >> 1;\n")
    if dir == 2: str.append("int sp_idx = ((x2==X2m1) ? X-X2X1mX1 : X+X1) >> 1;\n")
    if dir == 3: str.append("int sp_idx = ((x2==0)    ? X+X2X1mX1 : X-X1) >> 1;\n")
    if dir == 4: str.append("int sp_idx = ((x3==X3m1) ? X-X3X2X1mX2X1 : X+X2X1) >> 1;\n")
    if dir == 5: str.append("int sp_idx = ((x3==0)    ? X+X3X2X1mX2X1 : X-X2X1) >> 1;\n")
    if dir == 6: 
        str.append("#ifndef MULTI_GPU\n")
        str.append("    int sp_idx = ((x4==X4m1) ? X-X4X3X2X1mX3X2X1 : X+X3X2X1) >> 1;\n")
        str.append("#define sp_stride_t sp_stride\n")
        str.append("#define sp_norm_idx sp_idx\n")
        str.append("#else\n")
        str.append("    int sp_idx;\n")
        str.append("    int sp_stride_t;\n")
        str.append("#if (DD_PREC==2)\n")
        str.append("    int sp_norm_idx;\n")
        str.append("#else\n")
        str.append("#define sp_norm_idx sp_idx\n")
        str.append("#endif\n")
        str.append("    if (x4 == X4m1) { // front face (lower spin components)\n")
        str.append("      sp_stride_t = Vs;\n")
        str.append("      sp_idx = sid - (Vh - Vs) + SPINOR_HOP*sp_stride; // starts at Npad*Vs (precalculate more)\n")
        str.append("#if (DD_PREC==2)\n")
        str.append("      sp_norm_idx = sid - (Vh - Vs) + sp_stride + Vs; // need extra Vs addition since we require the 2nd norm buffer\n")
        str.append("#endif\n")
        str.append("    } else {\n")
        str.append("      sp_stride_t = sp_stride;\n")
        str.append("      sp_idx = (X+X3X2X1) >> 1;\n")
        str.append("#if (DD_PREC==2)\n")
        str.append("      sp_norm_idx = sp_idx;\n")
        str.append("#endif\n")
        str.append("    }\n")
        str.append("#endif // MULTI_GPU\n\n")
    if dir == 7: 
        str.append("#ifndef MULTI_GPU\n")
        str.append("    int sp_idx = ((x4==0)    ? X+X4X3X2X1mX3X2X1 : X-X3X2X1) >> 1;\n")
        str.append("#define sp_stride_t sp_stride\n")
        str.append("#define sp_norm_idx sp_idx\n")
        str.append("    int ga_idx = sp_idx;\n")
        str.append("#else\n")
        str.append("    int sp_idx;\n")
        str.append("    int sp_stride_t;\n")
        str.append("#if (DD_PREC==2)\n")
        str.append("    int sp_norm_idx;\n")
        str.append("#else\n")
        str.append("#define sp_norm_idx sp_idx\n")
        str.append("#endif\n")
        str.append("    if (x4 == 0) { // back face\n")
        str.append("      sp_stride_t = Vs;\n")
        str.append("      sp_idx = sid + SPINOR_HOP*sp_stride;\n")
        str.append("#if (DD_PREC==2)\n")
        str.append("      sp_norm_idx = sid + sp_stride;\n")
        str.append("#endif\n")
        str.append("    } else {\n")
        str.append("      sp_stride_t = sp_stride;\n")
        str.append("      sp_idx = (X - X3X2X1) >> 1;\n")
        str.append("#if (DD_PREC==2)\n")
        str.append("      sp_norm_idx = sp_idx;\n")
        str.append("#endif\n")
        str.append("    }\n")
        str.append("    // back links in pad, which is offset by Vh+sid from buffer start\n")
        str.append("    int ga_idx = (x4==0) ? sid+Vh : sp_idx;\n")
        str.append("#endif // MULTI_GPU\n\n")
    
    if dir != 7:
        ga_idx = "sid" if dir % 2 == 0 else "sp_idx"
        str.append("int ga_idx = "+ga_idx+";\n\n")
    
    # scan the projector to determine which loads are required
    row_cnt = ([0,0,0,0])
    for h in range(0,4):
        for s in range(0,4):
            re = proj(h,s).real
            im = proj(h,s).imag
            if re != 0 or im != 0:
                row_cnt[h] += 1
    row_cnt[0] += row_cnt[1]
    row_cnt[2] += row_cnt[3]

    load_spinor = []
    load_spinor.append("// read spinor from device memory\n")
    if row_cnt[0] == 0:
        load_spinor.append("READ_SPINOR_DOWN(SPINORTEX, sp_stride_t, sp_idx, sp_norm_idx);\n\n")
    elif row_cnt[2] == 0:
        load_spinor.append("READ_SPINOR_UP(SPINORTEX, sp_stride_t, sp_idx, sp_norm_idx);\n\n")
    else:
        load_spinor.append("READ_SPINOR(SPINORTEX, sp_stride, sp_idx, sp_idx);\n\n")

    load_gauge = []
    load_gauge.append("// read gauge matrix from device memory\n")
    load_gauge.append("READ_GAUGE_MATRIX(G, GAUGE"+`dir%2`+"TEX, "+`dir`+", ga_idx, ga_stride);\n\n")

    reconstruct_gauge = []
    reconstruct_gauge.append("// reconstruct gauge matrix\n")
    reconstruct_gauge.append("RECONSTRUCT_GAUGE_MATRIX("+`dir`+");\n\n")

    project = []
    project.append("// project spinor into half spinors\n")
    for h in range(0, 2):
        for c in range(0, 3):
            strRe = []
            strIm = []
            for s in range(0, 4):
                re = proj(h,s).real
                im = proj(h,s).imag
                if re==0 and im==0: ()
                elif im==0:
                    strRe.append(sign(re)+in_re(s,c))
                    strIm.append(sign(re)+in_im(s,c))
                elif re==0:
                    strRe.append(sign(-im)+in_im(s,c))
                    strIm.append(sign(im)+in_re(s,c))
            if row_cnt[0] == 0: #projector defined on lower half only
                for s in range(0, 4):
                    re = proj(h+2,s).real
                    im = proj(h+2,s).imag
                    if re==0 and im==0: ()
                    elif im==0:
                        strRe.append(sign(re)+in_re(s,c))
                        strIm.append(sign(re)+in_im(s,c))
                    elif re==0:
                        strRe.append(sign(-im)+in_im(s,c))
                        strIm.append(sign(im)+in_re(s,c))
                
            project.append("spinorFloat "+h1_re(h,c)+ " = "+''.join(strRe)+";\n")
            project.append("spinorFloat "+h1_im(h,c)+ " = "+''.join(strIm)+";\n")
        project.append("\n")
    
    ident = []
    ident.append("// identity gauge matrix\n")
    for m in range(0,3):
        for h in range(0,2):
            ident.append("spinorFloat "+h2_re(h,m)+" = " + h1_re(h,m) + "; ")
            ident.append("spinorFloat "+h2_im(h,m)+" = " + h1_im(h,m) + ";\n")
    ident.append("\n")
    
    mult = []
    for m in range(0,3):
        mult.append("// multiply row "+`m`+"\n")
        for h in range(0,2):
            re = ["spinorFloat "+h2_re(h,m)+" = 0;\n"]
            im = ["spinorFloat "+h2_im(h,m)+" = 0;\n"]
            for c in range(0,3):
                re.append(h2_re(h,m) + " += " + g_re(dir,m,c) + " * "+h1_re(h,c)+";\n")
                re.append(h2_re(h,m) + " -= " + g_im(dir,m,c) + " * "+h1_im(h,c)+";\n")
                im.append(h2_im(h,m) + " += " + g_re(dir,m,c) + " * "+h1_im(h,c)+";\n")
                im.append(h2_im(h,m) + " += " + g_im(dir,m,c) + " * "+h1_re(h,c)+";\n")
            mult.append(''.join(re))
            mult.append(''.join(im))
        mult.append("\n")
    
    reconstruct = []
    for m in range(0,3):

        for h in range(0,2):
            h_out = h
            if row_cnt[0] == 0: # projector defined on lower half only
                h_out = h+2
            reconstruct.append(out_re(h_out, m) + " += " + h2_re(h,m) + ";\n")
            reconstruct.append(out_im(h_out, m) + " += " + h2_im(h,m) + ";\n")
    
        for s in range(2,4):
            (h,c) = row(s)
            re = c.real
            im = c.imag
            if im == 0 and re == 0:
                ()
            elif im == 0:
                reconstruct.append(out_re(s, m) + " " + sign(re) + "= " + h2_re(h,m) + ";\n")
                reconstruct.append(out_im(s, m) + " " + sign(re) + "= " + h2_im(h,m) + ";\n")
            elif re == 0:
                reconstruct.append(out_re(s, m) + " " + sign(-im) + "= " + h2_im(h,m) + ";\n")
                reconstruct.append(out_im(s, m) + " " + sign(+im) + "= " + h2_re(h,m) + ";\n")
        
        reconstruct.append("\n")
        
    if dir >= 6:
        str.append("if (gauge_fixed && ga_idx < X4X3X2X1hmX3X2X1h) ")
        str.append(block(''.join(load_spinor) + ''.join(project) + ''.join(ident) + ''.join(reconstruct)))
        str.append(" else ")
        str.append(block(''.join(load_gauge) + ''.join(load_spinor) + ''.join(reconstruct_gauge) + 
                         ''.join(project) + ''.join(mult) + ''.join(reconstruct)))
    else:
        str.append(''.join(load_gauge) + ''.join(load_spinor) + ''.join(reconstruct_gauge) + 
                   ''.join(project) + ''.join(mult) + ''.join(reconstruct))
    
    if pack_only:
        out = ''.join(load_spinor) + ''.join(project)
        out = out.replace("sp_stride_t", "sp_stride")
        out = out.replace("sp_idx", "idx")
        out = out.replace("sp_norm_idx", "idx")
        return out
    else:
        return block(''.join(str))+"\n\n"
# end def gen


def to_chiral_basis(c):
    str = []

    str.append("spinorFloat "+a_re(0,0,c)+" = -"+out_re(1,c)+" - "+out_re(3,c)+";\n")
    str.append("spinorFloat "+a_im(0,0,c)+" = -"+out_im(1,c)+" - "+out_im(3,c)+";\n")
    str.append("spinorFloat "+a_re(0,1,c)+" =  "+out_re(0,c)+" + "+out_re(2,c)+";\n")
    str.append("spinorFloat "+a_im(0,1,c)+" =  "+out_im(0,c)+" + "+out_im(2,c)+";\n")
    str.append("spinorFloat "+a_re(0,2,c)+" = -"+out_re(1,c)+" + "+out_re(3,c)+";\n")
    str.append("spinorFloat "+a_im(0,2,c)+" = -"+out_im(1,c)+" + "+out_im(3,c)+";\n")
    str.append("spinorFloat "+a_re(0,3,c)+" =  "+out_re(0,c)+" - "+out_re(2,c)+";\n")
    str.append("spinorFloat "+a_im(0,3,c)+" =  "+out_im(0,c)+" - "+out_im(2,c)+";\n")
    str.append("\n")

    for s in range (0,4):
        str.append(out_re(s,c)+" = "+a_re(0,s,c)+";  ")
        str.append(out_im(s,c)+" = "+a_im(0,s,c)+";\n")

    return block(''.join(str))+"\n\n"
# end def to_chiral_basis


def from_chiral_basis(c): # note: factor of 1/2 is included in clover term normalization
    str = []
    str.append("spinorFloat "+a_re(0,0,c)+" =  "+out_re(1,c)+" + "+out_re(3,c)+";\n")
    str.append("spinorFloat "+a_im(0,0,c)+" =  "+out_im(1,c)+" + "+out_im(3,c)+";\n")
    str.append("spinorFloat "+a_re(0,1,c)+" = -"+out_re(0,c)+" - "+out_re(2,c)+";\n")
    str.append("spinorFloat "+a_im(0,1,c)+" = -"+out_im(0,c)+" - "+out_im(2,c)+";\n")
    str.append("spinorFloat "+a_re(0,2,c)+" =  "+out_re(1,c)+" - "+out_re(3,c)+";\n")
    str.append("spinorFloat "+a_im(0,2,c)+" =  "+out_im(1,c)+" - "+out_im(3,c)+";\n")
    str.append("spinorFloat "+a_re(0,3,c)+" = -"+out_re(0,c)+" + "+out_re(2,c)+";\n")
    str.append("spinorFloat "+a_im(0,3,c)+" = -"+out_im(0,c)+" + "+out_im(2,c)+";\n")
    str.append("\n")

    for s in range (0,4):
        str.append(out_re(s,c)+" = "+a_re(0,s,c)+";  ")
        str.append(out_im(s,c)+" = "+a_im(0,s,c)+";\n")

    return block(''.join(str))+"\n\n"
# end def from_chiral_basis


def clover_mult(chi):
    str = []
    str.append("READ_CLOVER(CLOVERTEX, "+`chi`+")\n")
    str.append("\n")

    for s in range (0,2):
        for c in range (0,3):
            str.append("spinorFloat "+a_re(chi,s,c)+" = 0; spinorFloat "+a_im(chi,s,c)+" = 0;\n")
    str.append("\n")

    for sm in range (0,2):
        for cm in range (0,3):
            for sn in range (0,2):
                for cn in range (0,3):
                    str.append(a_re(chi,sm,cm)+" += "+c_re(chi,sm,cm,sn,cn)+" * "+out_re(2*chi+sn,cn)+";\n")
                    if (sn != sm) or (cn != cm): 
                        str.append(a_re(chi,sm,cm)+" -= "+c_im(chi,sm,cm,sn,cn)+" * "+out_im(2*chi+sn,cn)+";\n")
                    #else: str.append(";\n")
                    str.append(a_im(chi,sm,cm)+" += "+c_re(chi,sm,cm,sn,cn)+" * "+out_im(2*chi+sn,cn)+";\n")
                    if (sn != sm) or (cn != cm): 
                        str.append(a_im(chi,sm,cm)+" += "+c_im(chi,sm,cm,sn,cn)+" * "+out_re(2*chi+sn,cn)+";\n")
                    #else: str.append(";\n")
            str.append("\n")

    for s in range (0,2):
        for c in range (0,3):
            str.append(out_re(2*chi+s,c)+" = "+a_re(chi,s,c)+";  ")
            str.append(out_im(2*chi+s,c)+" = "+a_im(chi,s,c)+";\n")
    str.append("\n")

    return block(''.join(str))+"\n\n"
# end def clover_mult


def apply_clover():
    str = []
    str.append("#ifdef DSLASH_CLOVER\n\n")
    str.append("// change to chiral basis\n")
    str.append(to_chiral_basis(0) + to_chiral_basis(1) + to_chiral_basis(2) + "\n")
    str.append("// apply first chiral block\n")
    str.append(clover_mult(0))
    str.append("// apply second chiral block\n")
    str.append(clover_mult(1))
    str.append("// change back from chiral basis\n")
    str.append("// (note: required factor of 1/2 is included in clover term normalization)\n")
    str.append(from_chiral_basis(0) + from_chiral_basis(1) + from_chiral_basis(2))
    str.append("#endif // DSLASH_CLOVER\n")

    return ''.join(str)+"\n"
# end def clover


def twisted_rotate(x):
    str = []
    str.append("// apply twisted mass rotation\n")

    for h in range(0, 4):
        for c in range(0, 3):
            strRe = []
            strIm = []
            for s in range(0, 4):
                # identity
                re = id[4*h+s].real
                im = id[4*h+s].imag
                if re==0 and im==0: ()
                elif im==0:
                    strRe.append(sign(re)+out_re(s,c))
                    strIm.append(sign(re)+out_im(s,c))
                elif re==0:
                    strRe.append(sign(-im)+out_im(s,c))
                    strIm.append(sign(im)+out_re(s,c))
                
                # sign(x)*i*mu*gamma_5
                re = igamma5[4*h+s].real
                im = igamma5[4*h+s].imag
                if re==0 and im==0: ()
                elif im==0:
                    strRe.append(sign(re*x)+out_re(s,c) + "*a")
                    strIm.append(sign(re*x)+out_im(s,c) + "*a")
                elif re==0:
                    strRe.append(sign(-im*x)+out_im(s,c) + "*a")
                    strIm.append(sign(im*x)+out_re(s,c) + "*a")

            str.append("volatile spinorFloat "+tmp_re(h,c)+ " = "+''.join(strRe)+";\n")
            str.append("volatile spinorFloat "+tmp_im(h,c)+ " = "+''.join(strIm)+";\n")
        str.append("\n")
    
    return ''.join(str)+"\n"


def twisted():
    str = []
    str.append(twisted_rotate(+1))

    str.append("#ifndef DSLASH_XPAY\n")
    str.append("//scale by b = 1/(1 + a*a) \n")
    for s in range(0,4):
        for c in range(0,3):
            str.append(out_re(s,c) + " = b*" + tmp_re(s,c) + ";\n")
            str.append(out_im(s,c) + " = b*" + tmp_im(s,c) + ";\n")
    str.append("#else\n")
    for s in range(0,4):
        for c in range(0,3):
            str.append(out_re(s,c) + " = " + tmp_re(s,c) + ";\n")
            str.append(out_im(s,c) + " = " + tmp_im(s,c) + ";\n")
    str.append("#endif // DSLASH_XPAY\n")
    str.append("\n")

    return block(''.join(str))+"\n"
# end def twisted


def epilog():
    str = []
    str.append(
"""
#ifdef DSLASH_XPAY
    READ_ACCUM(ACCUMTEX, sp_stride)
""")

    str.append("#ifdef SPINOR_DOUBLE\n")

    for s in range(0,4):
        for c in range(0,3):
            i = 3*s+c
            if twist == False:
                str.append("    "+out_re(s,c) +" = a*"+out_re(s,c)+" + accum"+nthFloat2(2*i+0)+";\n")
                str.append("    "+out_im(s,c) +" = a*"+out_im(s,c)+" + accum"+nthFloat2(2*i+1)+";\n")
            else:
                str.append("    "+out_re(s,c) +" = b*"+out_re(s,c)+" + accum"+nthFloat2(2*i+0)+";\n")
                str.append("    "+out_im(s,c) +" = b*"+out_im(s,c)+" + accum"+nthFloat2(2*i+1)+";\n")

    str.append("#else\n")

    for s in range(0,4):
        for c in range(0,3):
            i = 3*s+c
            if twist == False:
                str.append("    "+out_re(s,c) +" = a*"+out_re(s,c)+" + accum"+nthFloat4(2*i+0)+";\n")
                str.append("    "+out_im(s,c) +" = a*"+out_im(s,c)+" + accum"+nthFloat4(2*i+1)+";\n")
            else:
                str.append("    "+out_re(s,c) +" = b*"+out_re(s,c)+" + accum"+nthFloat4(2*i+0)+";\n")
                str.append("    "+out_im(s,c) +" = b*"+out_im(s,c)+" + accum"+nthFloat4(2*i+1)+";\n")
    str.append("#endif // SPINOR_DOUBLE\n")

    str.append("#endif // DSLASH_XPAY\n\n")
    
    str.append(
"""
    // write spinor field back to device memory
    WRITE_SPINOR(sp_stride);

""")

    str.append("// undefine to prevent warning when precision is changed\n")
    str.append("#undef spinorFloat\n")
    str.append("#undef SHARED_STRIDE\n\n")

    str.append("#undef A_re\n")
    str.append("#undef A_im\n\n")

    str.append("#ifdef sp_norm_idx\n")
    str.append("#undef sp_norm_idx\n")
    str.append("#endif\n")

    for m in range(0,3):
        for n in range(0,3):
            i = 3*m+n
            str.append("#undef "+g_re(0,m,n)+"\n")
            str.append("#undef "+g_im(0,m,n)+"\n")
    str.append("\n")

    for s in range(0,4):
        for c in range(0,3):
            i = 3*s+c
            str.append("#undef "+in_re(s,c)+"\n")
            str.append("#undef "+in_im(s,c)+"\n")
    str.append("\n")

    if clover == True:
        for m in range(0,6):
            s = m/3
            c = m%3
            str.append("#undef "+c_re(0,s,c,s,c)+"\n")
            for n in range(0,6):
                sn = n/3
                cn = n%3
                for m in range(n+1,6):
                    sm = m/3
                    cm = m%3
                    str.append("#undef "+c_re(0,sm,cm,sn,cn)+"\n")
                    str.append("#undef "+c_im(0,sm,cm,sn,cn)+"\n")
        str.append("\n")

    for s in range(0,4):
        for c in range(0,3):
            i = 3*s+c
            if 2*i < sharedFloats:
                str.append("#undef "+out_re(s,c)+"\n")
                if 2*i+1 < sharedFloats:
                    str.append("#undef "+out_im(s,c)+"\n")
    str.append("\n")

    return ''.join(str)
# end def epilog


def pack_face(facenum):
    str = []
    str.append("\nswitch(dim) {\n")
    for dim in range(0,4):
        str.append("case "+`dim`+":\n")
        proj = []
        proj.append(gen(2*dim+facenum, pack_only=True))
        proj.append("// write spinor field back to device memory\n")
        proj.append("WRITE_HALF_SPINOR(face_volume, face_idx);\n")
        str.append(indent(block(''.join(proj))+"\n"+"break;\n"))
    str.append("}\n\n")
    return ''.join(str)
# end def pack_face


def generate_pack():
    str = []
    str.append(def_input_spinor())
    str.append("#include \"io_spinor.h\"\n\n")

    str.append("if (face_num) ")
    str.append(block(pack_face(1)))
    str.append(" else ")
    str.append(block(pack_face(0)))

    str.append("\n\n")
    str.append("// undefine to prevent warning when precision is changed\n")
    str.append("#undef spinorFloat\n")
    str.append("#undef SHARED_STRIDE\n\n")

    for s in range(0,4):
        for c in range(0,3):
            i = 3*s+c
            str.append("#undef "+in_re(s,c)+"\n")
            str.append("#undef "+in_im(s,c)+"\n")
    str.append("\n")

    return ''.join(str)
# end def generate_pack


def generate():
    return prolog() + gen(0) + gen(1) + gen(2) + gen(3) + gen(4) + gen(5) + gen(6) + gen(7) + apply_clover() + epilog()

def generate_twisted():
    return prolog() + gen(0) + gen(1) + gen(2) + gen(3) + gen(4) + gen(5) + gen(6) + gen(7) + twisted() + epilog()


# To fit 192 threads/SM (single precision) with 16K shared memory, set sharedFloats to 19 or smaller
sharedFloats = 8

twist = False
clover = True
dagger = False
print sys.argv[0] + ": generating wilson_dslash_core.h";
f = open('dslash_core/wilson_dslash_core.h', 'w')
f.write(generate())
f.close()

dagger = True
print sys.argv[0] + ": generating wilson_dslash_dagger_core.h";
f = open('dslash_core/wilson_dslash_dagger_core.h', 'w')
f.write(generate())
f.close()

twist = True
clover = False
dagger = False
print sys.argv[0] + ": generating tm_dslash_core.h";
f = open('dslash_core/tm_dslash_core.h', 'w')
f.write(generate_twisted())
f.close()

dagger = True
print sys.argv[0] + ": generating tm_dslash_dagger_core.h";
f = open('dslash_core/tm_dslash_dagger_core.h', 'w')
f.write(generate_twisted())
f.close()

sharedFloats = 0
twist = False
clover = False
dagger = False
print sys.argv[0] + ": generating wilson_pack_face_core.h";
f = open('dslash_core/wilson_pack_face_core.h', 'w')
f.write(generate_pack())
f.close()

dagger = True
print sys.argv[0] + ": generating wilson_pack_face_dagger_core.h";
f = open('dslash_core/wilson_pack_face_dagger_core.h', 'w')
f.write(generate_pack())
f.close()

#f = open('clover_core.h', 'w')
#f.write(prolog() + clover() + epilog())
#f.close()
