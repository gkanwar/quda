#include <iostream>
#include <dirac_quda.h>
#include <blas_quda.h>

namespace quda {

  namespace mobius {
#include <dslash_init.cuh>
  }

  DiracMobius::DiracMobius(const DiracParam &param) : DiracDomainWall(param) {
    memcpy(b_5, param.b_5, sizeof(double)*param.Ls);
    memcpy(c_5, param.c_5, sizeof(double)*param.Ls);
    mobius::initConstants(*param.gauge, profile);
  }

  DiracMobius::DiracMobius(const DiracMobius &dirac) : DiracDomainWall(dirac) {
    memcpy(b_5, dirac.b_5, Ls);
    memcpy(c_5, dirac.c_5, Ls);
    mobius::initConstants(*dirac.gauge, profile);
  }

  DiracMobius::~DiracMobius() { }

  DiracMobius& DiracMobius::operator=(const DiracMobius &dirac)
  {
    if (&dirac != this) {
      DiracDomainWall::operator=(dirac);
      memcpy(b_5, dirac.b_5, Ls);
      memcpy(c_5, dirac.c_5, Ls);
    }

    return *this;
  }

// Modification for the 4D preconditioned Mobius domain wall operator
  void DiracMobius::Dslash4(ColorSpinorField &out, const ColorSpinorField &in,
			    const QudaParity parity) const
  {
    if ( in.Ndim() != 5 || out.Ndim() != 5) errorQuda("Wrong number of dimensions\n");
    checkParitySpinor(in, out);
    checkSpinorAlias(in, out);
 
    mobius::initMDWFConstants(b_5, c_5, in.X(4), m5, profile);

    MDWFDslashCuda(&static_cast<cudaColorSpinorField&>(out), *gauge,
		   &static_cast<const cudaColorSpinorField&>(in),
		   parity, dagger, 0, mass, 0, commDim, 0, profile);   

    flops += 1320LL*(long long)in.Volume();
  }
  
  void DiracMobius::Dslash4pre(ColorSpinorField &out, const ColorSpinorField &in, const QudaParity parity) const
  {
    if ( in.Ndim() != 5 || out.Ndim() != 5) errorQuda("Wrong number of dimensions\n");
    checkParitySpinor(in, out);
    checkSpinorAlias(in, out);
 
    mobius::initMDWFConstants(b_5, c_5, in.X(4), m5, profile);

    MDWFDslashCuda(&static_cast<cudaColorSpinorField&>(out), *gauge,
		   &static_cast<const cudaColorSpinorField&>(in),
		   parity, dagger, 0, mass, 0, commDim, 1, profile);   

    long long Ls = in.X(4);
    long long bulk = (Ls-2)*(in.Volume()/Ls);
    long long wall = 2*in.Volume()/Ls;
    flops += 72LL*(long long)in.Volume() + 96LL*bulk + 120LL*wall;
  }

  void DiracMobius::Dslash5(ColorSpinorField &out, const ColorSpinorField &in, const QudaParity parity) const
  {
    if ( in.Ndim() != 5 || out.Ndim() != 5) errorQuda("Wrong number of dimensions\n");
    checkParitySpinor(in, out);
    checkSpinorAlias(in, out);
 
    mobius::initMDWFConstants(b_5, c_5, in.X(4), m5, profile);
    
    MDWFDslashCuda(&static_cast<cudaColorSpinorField&>(out), *gauge,
		   &static_cast<const cudaColorSpinorField&>(in),
		   parity, dagger, 0, mass, 0, commDim, 2, profile);   

    long long Ls = in.X(4);
    long long bulk = (Ls-2)*(in.Volume()/Ls);
    long long wall = 2*in.Volume()/Ls;
    flops += 48LL*(long long)in.Volume() + 96LL*bulk + 120LL*wall;
  }

  // Modification for the 4D preconditioned Mobius domain wall operator
  void DiracMobius::Dslash4Xpay(ColorSpinorField &out, const ColorSpinorField &in,
				const QudaParity parity, const ColorSpinorField &x, const double &k) const
  {
    if ( in.Ndim() != 5 || out.Ndim() != 5) errorQuda("Wrong number of dimensions\n");

    checkParitySpinor(in, out);
    checkSpinorAlias(in, out);

    mobius::initMDWFConstants(b_5, c_5, in.X(4), m5, profile);

    MDWFDslashCuda(&static_cast<cudaColorSpinorField&>(out), *gauge,
		   &static_cast<const cudaColorSpinorField&>(in),
		   parity, dagger, &static_cast<const cudaColorSpinorField&>(x),
		   mass, k, commDim, 0, profile);

    flops += (1320LL+48LL)*(long long)in.Volume();
  }

  void DiracMobius::Dslash4preXpay(ColorSpinorField &out, const ColorSpinorField &in,
				   const QudaParity parity, const ColorSpinorField &x, const double &k) const
  {
    if ( in.Ndim() != 5 || out.Ndim() != 5) errorQuda("Wrong number of dimensions\n");

    checkParitySpinor(in, out);
    checkSpinorAlias(in, out);

    mobius::initMDWFConstants(b_5, c_5, in.X(4), m5, profile);

    MDWFDslashCuda(&static_cast<cudaColorSpinorField&>(out), *gauge,
		   &static_cast<const cudaColorSpinorField&>(in),
		   parity, dagger, &static_cast<const cudaColorSpinorField&>(x),
		   mass, k, commDim, 1, profile);

    long long Ls = in.X(4);
    long long bulk = (Ls-2)*(in.Volume()/Ls);
    long long wall = 2*in.Volume()/Ls;
    flops += (72LL+48LL)*(long long)in.Volume() + 96LL*bulk + 120LL*wall;
  }

  // The xpay operator bakes in a factor of kappa_b^2
  void DiracMobius::Dslash5Xpay(ColorSpinorField &out, const ColorSpinorField &in,
				const QudaParity parity, const ColorSpinorField &x, const double &k) const
  {
    if ( in.Ndim() != 5 || out.Ndim() != 5) errorQuda("Wrong number of dimensions\n");
    checkParitySpinor(in, out);
    checkSpinorAlias(in, out);

    mobius::initMDWFConstants(b_5, c_5, in.X(4), m5, profile);

    MDWFDslashCuda(&static_cast<cudaColorSpinorField&>(out), *gauge,
		   &static_cast<const cudaColorSpinorField&>(in),
		   parity, dagger, &static_cast<const cudaColorSpinorField&>(x),
		   mass, k, commDim, 2, profile);

    long long Ls = in.X(4);
    long long bulk = (Ls-2)*(in.Volume()/Ls);
    long long wall = 2*in.Volume()/Ls;
    flops += (96LL)*(long long)in.Volume() + 96LL*bulk + 120LL*wall;
  }

  void DiracMobius::M(ColorSpinorField &out, const ColorSpinorField &in) const
  {
    if ( in.Ndim() != 5 || out.Ndim() != 5) errorQuda("Wrong number of dimensions\n");

    bool reset = newTmp(&tmp1, in);
    checkFullSpinor(*tmp1, in);

    // FIXME broken for variable coefficients
    double kappa_b = 0.5 / (b_5[0]*(4.0+m5)+1.0);

    // cannot use Xpay variants since it will scale incorrectly for this operator

    Dslash4pre(out.Odd(), in.Even(), QUDA_EVEN_PARITY);
    Dslash4(tmp1->Even(), out.Odd(), QUDA_ODD_PARITY);
    Dslash5(out.Odd(), in.Odd(), QUDA_ODD_PARITY);
    blas::axpy(-kappa_b, tmp1->Even(), out.Odd());

    Dslash4pre(out.Even(), in.Odd(), QUDA_ODD_PARITY);
    Dslash4(tmp1->Odd(), out.Even(), QUDA_EVEN_PARITY);
    Dslash5(out.Even(), in.Even(), QUDA_EVEN_PARITY);
    blas::axpy(-kappa_b, tmp1->Odd(), out.Even());

    deleteTmp(&tmp1, reset);
  }

  void DiracMobius::MdagM(ColorSpinorField &out, const ColorSpinorField &in) const
  {
    checkFullSpinor(out, in);

    bool reset = newTmp(&tmp2, in);

    M(*tmp2, in);
    Mdag(out, *tmp2);

    deleteTmp(&tmp2, reset);
  }

  void DiracMobius::prepare(ColorSpinorField* &src, ColorSpinorField* &sol, ColorSpinorField &x, ColorSpinorField &b,
			    const QudaSolutionType solType) const
  {
    if (solType == QUDA_MATPC_SOLUTION || solType == QUDA_MATPCDAG_MATPC_SOLUTION) {
      errorQuda("Preconditioned solution requires a preconditioned solve_type");
    }

    src = &b;
    sol = &x;
  }

  void DiracMobius::reconstruct(ColorSpinorField &x, const ColorSpinorField &b, const QudaSolutionType solType) const
  {
    // do nothing
  }


  DiracMobiusPC::DiracMobiusPC(const DiracParam &param) : DiracMobius(param) {  }

  DiracMobiusPC::DiracMobiusPC(const DiracMobiusPC &dirac) : DiracMobius(dirac) {  }

  DiracMobiusPC::~DiracMobiusPC() { }

  DiracMobiusPC& DiracMobiusPC::operator=(const DiracMobiusPC &dirac)
  {
    if (&dirac != this) {
      DiracMobius::operator=(dirac);
    }

    return *this;
  }

  void DiracMobiusPC::Dslash5inv(ColorSpinorField &out, const ColorSpinorField &in, const QudaParity parity) const
  {
    if ( in.Ndim() != 5 || out.Ndim() != 5) errorQuda("Wrong number of dimensions\n");

    checkParitySpinor(in, out);
    checkSpinorAlias(in, out);

    mobius::initMDWFConstants(b_5, c_5, in.X(4), m5, profile);

    MDWFDslashCuda(&static_cast<cudaColorSpinorField&>(out), *gauge,
		   &static_cast<const cudaColorSpinorField&>(in),
		   parity, dagger, 0, mass, 0, commDim, 3, profile);

    long long Ls = in.X(4);
    flops += 144LL*(long long)in.Volume()*Ls + 3LL*Ls*(Ls-1LL);
  }

  // The xpay operator bakes in a factor of kappa_b^2
  void DiracMobiusPC::Dslash5invXpay(ColorSpinorField &out, const ColorSpinorField &in,
					       const QudaParity parity, const ColorSpinorField &x, const double &k) const
  {
    if ( in.Ndim() != 5 || out.Ndim() != 5) errorQuda("Wrong number of dimensions\n");

    checkParitySpinor(in, out);
    checkSpinorAlias(in, out);

    mobius::initMDWFConstants(b_5, c_5, in.X(4), m5, profile);

    MDWFDslashCuda(&static_cast<cudaColorSpinorField&>(out), *gauge,
		   &static_cast<const cudaColorSpinorField&>(in),
		   parity, dagger, &static_cast<const cudaColorSpinorField&>(x),
		   mass, k, commDim, 3, profile);

    long long Ls = in.X(4);
    flops +=  (144LL*Ls + 48LL)*(long long)in.Volume() + 3LL*Ls*(Ls-1LL);
  }

  // Apply the even-odd preconditioned mobius DWF operator
  //Actually, Dslash5 will return M5 operation and M5 = 1 + 0.5*kappa_b/kappa_c * D5
  void DiracMobiusPC::M(ColorSpinorField &out, const ColorSpinorField &in) const
  {
    if ( in.Ndim() != 5 || out.Ndim() != 5) errorQuda("Wrong number of dimensions\n");

    bool reset1 = newTmp(&tmp1, in);

    int odd_bit = (matpcType == QUDA_MATPC_ODD_ODD || matpcType == QUDA_MATPC_ODD_ODD_ASYMMETRIC) ? 1 : 0;
    bool symmetric =(matpcType == QUDA_MATPC_EVEN_EVEN || matpcType == QUDA_MATPC_ODD_ODD) ? true : false;
    QudaParity parity[2] = {static_cast<QudaParity>((1 + odd_bit) % 2), static_cast<QudaParity>((0 + odd_bit) % 2)};

    //QUDA_MATPC_EVEN_EVEN_ASYMMETRIC : M5 - kappa_b^2 * D4_{eo}D4pre_{oe}D5inv_{ee}D4_{eo}D4pre_{oe}
    //QUDA_MATPC_ODD_ODD_ASYMMETRIC : M5 - kappa_b^2 * D4_{oe}D4pre_{eo}D5inv_{oo}D4_{oe}D4pre_{eo}
    if (symmetric && !dagger) {
      Dslash4pre(*tmp1, in, parity[1]);
      Dslash4(out, *tmp1, parity[0]);
      Dslash5inv(*tmp1, out, parity[0]);
      Dslash4pre(out, *tmp1, parity[0]);
      Dslash4(*tmp1, out, parity[1]);
      Dslash5invXpay(out, *tmp1, parity[1], in, -1.0);
    } else if (symmetric && dagger) {
      Dslash5inv(*tmp1, in, parity[1]);
      Dslash4(out, *tmp1, parity[0]);
      Dslash4pre(*tmp1, out, parity[0]);
      Dslash5inv(out, *tmp1, parity[0]);
      Dslash4(*tmp1, out, parity[1]);
      Dslash4preXpay(out, *tmp1, parity[1], in, -1.0);
    } else if (!symmetric && !dagger) {
      Dslash4pre(*tmp1, in, parity[1]);
      Dslash4(out, *tmp1, parity[0]);
      Dslash5inv(*tmp1, out, parity[0]);
      Dslash4pre(out, *tmp1, parity[0]);
      Dslash4(*tmp1, out, parity[1]);
      Dslash5Xpay(out, in, parity[1], *tmp1, -1.0);
    } else if (!symmetric && dagger) {
      Dslash4(*tmp1, in, parity[0]);
      Dslash4pre(out, *tmp1, parity[0]);
      Dslash5inv(*tmp1, out, parity[0]);
      Dslash4(out, *tmp1, parity[1]);
      Dslash4pre(*tmp1, out, parity[1]);
      Dslash5Xpay(out, in, parity[1], *tmp1, -1.0);
    }

    deleteTmp(&tmp1, reset1);
  }

  void DiracMobiusPC::MdagM(ColorSpinorField &out, const ColorSpinorField &in) const
  {
    bool reset = newTmp(&tmp2, in);
    M(*tmp2, in);
    Mdag(out, *tmp2);
    deleteTmp(&tmp2, reset);
  }

  void DiracMobiusPC::prepare(ColorSpinorField* &src, ColorSpinorField* &sol,
      ColorSpinorField &x, ColorSpinorField &b, 
      const QudaSolutionType solType) const
  {
    // we desire solution to preconditioned system
    if (solType == QUDA_MATPC_SOLUTION || solType == QUDA_MATPCDAG_MATPC_SOLUTION) {
      src = &b;
      sol = &x;
    } else { // we desire solution to full system
      // prepare function in MDWF is not tested yet.
      bool reset = newTmp(&tmp1, b.Even());

      if (matpcType == QUDA_MATPC_EVEN_EVEN) {
	// src = D5^-1 (b_e + k D4_eo * D4pre * D5^-1 b_o)
	src = &(x.Odd());
	Dslash5inv(*tmp1, b.Odd(), QUDA_ODD_PARITY);
        Dslash4pre(*src, *tmp1, QUDA_ODD_PARITY);
        Dslash4Xpay(*tmp1, *src, QUDA_EVEN_PARITY, b.Even(), 1.0);
	Dslash5inv(*src, *tmp1, QUDA_EVEN_PARITY);
        sol = &(x.Even());
      } else if (matpcType == QUDA_MATPC_ODD_ODD) {
        // src = b_o + k D4_oe * D4pre * D5inv b_e
        src = &(x.Even());
        Dslash5inv(*tmp1, b.Even(), QUDA_EVEN_PARITY);
        Dslash4pre(*src, *tmp1, QUDA_EVEN_PARITY);
        Dslash4Xpay(*tmp1, *src, QUDA_ODD_PARITY, b.Odd(), 1.0);
	Dslash5inv(*src, *tmp1, QUDA_ODD_PARITY);
        sol = &(x.Odd());
      } else if (matpcType == QUDA_MATPC_EVEN_EVEN_ASYMMETRIC) {
        // src = b_e + k D4_eo * D4pre * D5inv b_o
        src = &(x.Odd());
        Dslash5inv(*src, b.Odd(), QUDA_ODD_PARITY);
        Dslash4pre(*tmp1, *src, QUDA_ODD_PARITY);
        Dslash4Xpay(*src, *tmp1, QUDA_EVEN_PARITY, b.Even(), 1.0);
        sol = &(x.Even());
      } else if (matpcType == QUDA_MATPC_ODD_ODD_ASYMMETRIC) {
        // src = b_o + k D4_oe * D4pre * D5inv b_e
        src = &(x.Even());
        Dslash5inv(*src, b.Even(), QUDA_EVEN_PARITY);
        Dslash4pre(*tmp1, *src, QUDA_EVEN_PARITY);
        Dslash4Xpay(*src, *tmp1, QUDA_ODD_PARITY, b.Odd(), 1.0);
        sol = &(x.Odd());
      } else {
        errorQuda("MatPCType %d not valid for DiracMobiusPC", matpcType);
      }
      // here we use final solution to store parity solution and parity source
      // b is now up for grabs if we want

      deleteTmp(&tmp1, reset);
    }
  }

  void DiracMobiusPC::reconstruct(ColorSpinorField &x, const ColorSpinorField &b,
      const QudaSolutionType solType) const
  {
    if (solType == QUDA_MATPC_SOLUTION || solType == QUDA_MATPCDAG_MATPC_SOLUTION) {
      return;
    }				

    bool reset1 = newTmp(&tmp1, x.Even());

    // create full solution
    checkFullSpinor(x, b);
    if (matpcType == QUDA_MATPC_EVEN_EVEN ||
	matpcType == QUDA_MATPC_EVEN_EVEN_ASYMMETRIC) {
      // psi_o = M5^-1 (b_o + k_b D4_oe D4pre x_e)
      Dslash4pre(x.Odd(), x.Even(), QUDA_EVEN_PARITY);
      Dslash4Xpay(*tmp1, x.Odd(), QUDA_ODD_PARITY, b.Odd(), 1.0);
      Dslash5inv(x.Odd(), *tmp1, QUDA_ODD_PARITY);
    } else if (matpcType == QUDA_MATPC_ODD_ODD ||
	       matpcType == QUDA_MATPC_ODD_ODD_ASYMMETRIC) {
      // psi_e = M5^-1 (b_e + k_b D4_eo D4pre x_o)
      Dslash4pre(x.Even(), x.Odd(), QUDA_ODD_PARITY);
      Dslash4Xpay(*tmp1, x.Even(), QUDA_EVEN_PARITY, b.Even(), 1.0);
      Dslash5inv(x.Even(), *tmp1, QUDA_EVEN_PARITY);
    } else {
      errorQuda("MatPCType %d not valid for DiracMobiusPC", matpcType);
    }

    deleteTmp(&tmp1, reset1);
  }

} // namespace quda
