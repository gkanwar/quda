
namespace quda {

  // For coarsening un-preconditioned operators we use uni-directional
  // coarsening to reduce the set up code.  For debugging we can force
  // bi-directional coarsening.
  static bool bidirectional_debug = false;

  template <typename Float, typename coarseGauge, typename fineGauge, typename fineSpinor,
	    typename fineSpinorTmp, typename fineClover>
  struct CalculateYArg {

    coarseGauge Y;           /** Computed coarse link field */
    coarseGauge X;           /** Computed coarse clover field */
    coarseGauge Xinv;        /** Computed coarse clover field */

    fineSpinorTmp UV;        /** Temporary that stores the fine-link * spinor field product */
    fineSpinor AV;           /** Temporary that stores the clover * spinor field product */

    const fineGauge U;       /** Fine grid link field */
    const fineSpinor V;      /** Fine grid spinor field */
    const fineClover C;      /** Fine grid clover field */
    const fineClover Cinv;   /** Fine grid clover field */

    int x_size[QUDA_MAX_DIM];   /** Dimensions of fine grid */
    int xc_size[QUDA_MAX_DIM];  /** Dimensions of coarse grid */

    int geo_bs[QUDA_MAX_DIM];   /** Geometric block dimensions */
    const int spin_bs;          /** Spin block size */

    int comm_dim[QUDA_MAX_DIM]; /** Node parition array */

    Float kappa;                /** kappa value */
    Float mu;                   /** mu value */
    Float mu_factor;            /** multiplicative factor for mu applied when mu is added to the operator */

    const int fineVolumeCB;     /** Fine grid volume */
    const int coarseVolumeCB;   /** Coarse grid volume */

    CalculateYArg(coarseGauge &Y, coarseGauge &X, coarseGauge &Xinv, fineSpinorTmp &UV, fineSpinor &AV, const fineGauge &U, const fineSpinor &V,
		  const fineClover &C, const fineClover &Cinv, double kappa, double mu, double mu_factor, const int *x_size_, const int *xc_size_, int *geo_bs_, int spin_bs_)
      : Y(Y), X(X), Xinv(Xinv), UV(UV), AV(AV), U(U), V(V), C(C), Cinv(Cinv), spin_bs(spin_bs_), kappa(static_cast<Float>(kappa)), mu(static_cast<Float>(mu)),
	mu_factor(static_cast<Float>(mu_factor)), fineVolumeCB(V.VolumeCB()), coarseVolumeCB(X.VolumeCB())
    {
      if (V.GammaBasis() != QUDA_DEGRAND_ROSSI_GAMMA_BASIS)
	errorQuda("Gamma basis %d not supported", V.GammaBasis());

      for (int i=0; i<QUDA_MAX_DIM; i++) {
	x_size[i] = x_size_[i];
	xc_size[i] = xc_size_[i];
	geo_bs[i] = geo_bs_[i];
	comm_dim[i] = comm_dim_partitioned(i);
      }
    }
  };

  /**
     Calculates the matrix UV^{s,c'}_mu(x) = \sum_c U^{c}_mu(x) * V^{s,c}_mu(x+mu)
     Where: mu = dir, s = fine spin, c' = coarse color, c = fine color
  */
  template<bool from_coarse, typename Float, int dim, QudaDirection dir, int fineSpin, int fineColor, int coarseSpin, int coarseColor, typename Arg>
  __device__ __host__ inline void computeUV(Arg &arg, int parity, int x_cb, int ic_c) {

    // only for preconditioned clover is V != AV
    auto &W = (dir == QUDA_FORWARDS) ? arg.V : arg.AV;

    int coord[5];
    coord[4] = 0;
    getCoords(coord, x_cb, arg.x_size, parity);

    constexpr int uvSpin = fineSpin * (from_coarse ? 2 : 1);

    complex<Float> UV[uvSpin][fineColor];

    for(int s = 0; s < uvSpin; s++) {
      for(int c = 0; c < fineColor; c++) {
	UV[s][c] = static_cast<Float>(0.0);
      }
    }

    if ( arg.comm_dim[dim] && (coord[dim] + 1 >= arg.x_size[dim]) ) {
      int nFace = 1;
      int ghost_idx = ghostFaceIndex<1>(coord, arg.x_size, dim, nFace);

      for(int s = 0; s < fineSpin; s++) {  //Fine Spin
	for(int ic = 0; ic < fineColor; ic++) { //Fine Color rows of gauge field
	  for(int jc = 0; jc < fineColor; jc++) {  //Fine Color columns of gauge field
	    if (!from_coarse)
	      UV[s][ic] += arg.U(dim, parity, x_cb, ic, jc) * W.Ghost(dim, 1, (parity+1)&1, ghost_idx, s, jc, ic_c);
	    else
	      for (int s_col=0; s_col<fineSpin; s_col++) {
		// on the coarse lattice if forwards then use the forwards links
		UV[s_col*fineSpin+s][ic] += arg.U(dim + (dir == QUDA_FORWARDS ? 4 : 0), parity, x_cb, s, s_col, ic, jc) *
		  W.Ghost(dim, 1, (parity+1)&1, ghost_idx, s_col, jc, ic_c);
	      } // which chiral block
	  }  //Fine color columns
	}  //Fine color rows
      }  //Fine Spin

    } else {
      int y_cb = linkIndexP1(coord, arg.x_size, dim);

      for(int s = 0; s < fineSpin; s++) {  //Fine Spin
	for(int ic = 0; ic < fineColor; ic++) { //Fine Color rows of gauge field
	  for(int jc = 0; jc < fineColor; jc++) {  //Fine Color columns of gauge field
	    if (!from_coarse)
	      UV[s][ic] += arg.U(dim, parity, x_cb, ic, jc) * W((parity+1)&1, y_cb, s, jc, ic_c);
	    else
	      for (int s_col=0; s_col<fineSpin; s_col++) {
		// on the coarse lattice if forwards then use the forwards links
		UV[s_col*fineSpin+s][ic] +=
		  arg.U(dim + (dir == QUDA_FORWARDS ? 4 : 0), parity, x_cb, s, s_col, ic, jc) *
		  W((parity+1)&1, y_cb, s_col, jc, ic_c);
	      } // which chiral block
	  }  //Fine color columns
	}  //Fine color rows
      }  //Fine Spin

    }


    for(int s = 0; s < uvSpin; s++) {
      for(int c = 0; c < fineColor; c++) {
	arg.UV(parity,x_cb,s,c,ic_c) = UV[s][c];
      }
    }


  } // computeUV

  template<bool from_coarse, typename Float, int dim, QudaDirection dir, int fineSpin, int fineColor, int coarseSpin, int coarseColor, typename Arg>
  void ComputeUVCPU(Arg &arg) {
    for (int parity=0; parity<2; parity++) {
      for (int x_cb=0; x_cb<arg.fineVolumeCB; x_cb++) {
	for (int ic_c=0; ic_c < coarseColor; ic_c++) // coarse color
	  computeUV<from_coarse,Float,dim,dir,fineSpin,fineColor,coarseSpin,coarseColor,Arg>(arg, parity, x_cb, ic_c);
      } // c/b volume
    }   // parity
  }

  template<bool from_coarse, typename Float, int dim, QudaDirection dir, int fineSpin, int fineColor, int coarseSpin, int coarseColor, typename Arg>
  __global__ void ComputeUVGPU(Arg arg) {
    int x_cb = blockDim.x*blockIdx.x + threadIdx.x;
    if (x_cb >= arg.fineVolumeCB) return;

    int parity = blockDim.y*blockIdx.y + threadIdx.y;
    int ic_c = blockDim.z*blockIdx.z + threadIdx.z; // coarse color
    if (ic_c >= coarseColor) return;
    computeUV<from_coarse,Float,dim,dir,fineSpin,fineColor,coarseSpin,coarseColor,Arg>(arg, parity, x_cb, ic_c);
  }

  /**
     Calculates the matrix A V^{s,c'}(x) = \sum_c A^{c}(x) * V^{s,c}(x)
     Where: s = fine spin, c' = coarse color, c = fine color
  */
  template<typename Float, int fineSpin, int fineColor, int coarseColor, typename Arg>
  __device__ __host__ inline void computeAV(Arg &arg, int parity, int x_cb, int ic_c) {

    for(int s = 0; s < fineSpin; s++) {
      for(int c = 0; c < fineColor; c++) {
	arg.AV(parity,x_cb,s,c,ic_c) = static_cast<Float>(0.0);
      }
    }

    for(int s = 0; s < fineSpin; s++) {  //Fine Spin
      const int s_c = s/arg.spin_bs;

      //On the fine lattice, the clover field is chirally blocked, so loop over rows/columns
      //in the same chiral block.
      for(int s_col = s_c*arg.spin_bs; s_col < (s_c+1)*arg.spin_bs; s_col++) { //Loop over fine spin column

	for(int ic = 0; ic < fineColor; ic++) { //Fine Color rows of gauge field
	  for(int jc = 0; jc < fineColor; jc++) {  //Fine Color columns of gauge field
	    arg.AV(parity, x_cb, s, ic, ic_c) +=
	      arg.Cinv(0, parity, x_cb, s, s_col, ic, jc) * arg.V(parity, x_cb, s_col, jc, ic_c);
	  }  //Fine color columns
	}  //Fine color rows
      }
    } //Fine Spin

  } // computeAV

  template<typename Float, int fineSpin, int fineColor, int coarseColor, typename Arg>
  void ComputeAVCPU(Arg &arg) {
    for (int parity=0; parity<2; parity++) {
      for (int x_cb=0; x_cb<arg.fineVolumeCB; x_cb++) {
	for (int ic_c=0; ic_c < coarseColor; ic_c++) // coarse color
	  computeAV<Float,fineSpin,fineColor,coarseColor,Arg>(arg, parity, x_cb, ic_c);
      } // c/b volume
    }   // parity
  }

  template<typename Float, int fineSpin, int fineColor, int coarseColor, typename Arg>
  __global__ void ComputeAVGPU(Arg arg) {
    int x_cb = blockDim.x*blockIdx.x + threadIdx.x;
    if (x_cb >= arg.fineVolumeCB) return;

    int parity = blockDim.y*blockIdx.y + threadIdx.y;
    int ic_c = blockDim.z*blockIdx.z + threadIdx.z; // coarse color
    if (ic_c >= coarseColor) return;
    computeAV<Float,fineSpin,fineColor,coarseColor,Arg>(arg, parity, x_cb, ic_c);
  }

  /**
     Calculates the matrix A V^{s,c'}(x) = \sum_c A^{c}(x) * V^{s,c}(x) for twisted-mass fermions
     Where: s = fine spin, c' = coarse color, c = fine color
  */
  template<typename Float, int fineSpin, int fineColor, int coarseColor, typename Arg>
  __device__ __host__ inline void computeTMAV(Arg &arg, int parity, int x_cb, int v) {

    complex<Float> fp(1./(1.+arg.mu*arg.mu),-arg.mu/(1.+arg.mu*arg.mu));
    complex<Float> fm(1./(1.+arg.mu*arg.mu),+arg.mu/(1.+arg.mu*arg.mu));

    for(int s = 0; s < fineSpin/2; s++) {
      for(int c = 0; c < fineColor; c++) {
	arg.AV(parity,x_cb,s,c,v) = arg.V(parity,x_cb,s,c,v)*fp;
      }
    }

    for(int s = fineSpin/2; s < fineSpin; s++) {
      for(int c = 0; c < fineColor; c++) {
	arg.AV(parity,x_cb,s,c,v) = arg.V(parity,x_cb,s,c,v)*fm;
      }
    }

  } // computeTMAV

  template<typename Float, int fineSpin, int fineColor, int coarseColor, typename Arg>
  void ComputeTMAVCPU(Arg &arg) {
    for (int parity=0; parity<2; parity++) {
      for (int x_cb=0; x_cb<arg.fineVolumeCB; x_cb++) {
	for (int v=0; v<coarseColor; v++) // coarse color
	  computeTMAV<Float,fineSpin,fineColor,coarseColor,Arg>(arg, parity, x_cb, v);
      } // c/b volume
    }   // parity
  }

  template<typename Float, int fineSpin, int fineColor, int coarseColor, typename Arg>
  __global__ void ComputeTMAVGPU(Arg arg) {
    int x_cb = blockDim.x*blockIdx.x + threadIdx.x;
    if (x_cb >= arg.fineVolumeCB) return;

    int parity = blockDim.y*blockIdx.y + threadIdx.y;
    int v = blockDim.z*blockIdx.z + threadIdx.z; // coarse color
    if (v >= coarseColor) return;

    computeTMAV<Float,fineSpin,fineColor,coarseColor,Arg>(arg, parity, x_cb, v);
  }

#ifdef DYNAMIC_CLOVER
  #ifdef UGLY_DYNCLOV
    #include<dyninv_clover_mg.cuh>
  #else

  template<typename Float, int fineSpin, int fineColor, int coarseColor, typename Arg>
  __device__ __host__ inline void applyInvClover(Arg &arg, int parity, int x_cb) {
    /* Applies the inverse of the clover term squared plus mu2 to the spinor */
    /* Compute (T^2 + mu2) first, then invert */
    /* We proceed by chiral blocks */

    for (int ch = 0; ch < 2; ch++) {	/* Loop over chiral blocks */
      Float diag[6], tmp[6];
      complex<Float> tri[15];	/* Off-diagonal components of the inverse clover term */

      /*	This macro avoid the infinitely long expansion of the tri products	*/

      #define Cl(s1,c1,s2,c2) (arg.C(0, parity, x_cb, s1+2*ch, s2+2*ch, c1, c2))

      tri[0]  = Cl(0,1,0,0)*Cl(0,0,0,0).real() + Cl(0,1,0,1)*Cl(0,1,0,0) + Cl(0,1,0,2)*Cl(0,2,0,0) + Cl(0,1,1,0)*Cl(1,0,0,0) + Cl(0,1,1,1)*Cl(1,1,0,0) + Cl(0,1,1,2)*Cl(1,2,0,0);
      tri[1]  = Cl(0,2,0,0)*Cl(0,0,0,0).real() + Cl(0,2,0,2)*Cl(0,2,0,0) + Cl(0,2,0,1)*Cl(0,1,0,0) + Cl(0,2,1,0)*Cl(1,0,0,0) + Cl(0,2,1,1)*Cl(1,1,0,0) + Cl(0,2,1,2)*Cl(1,2,0,0);
      tri[3]  = Cl(1,0,0,0)*Cl(0,0,0,0).real() + Cl(1,0,1,0)*Cl(1,0,0,0) + Cl(1,0,0,1)*Cl(0,1,0,0) + Cl(1,0,0,2)*Cl(0,2,0,0) + Cl(1,0,1,1)*Cl(1,1,0,0) + Cl(1,0,1,2)*Cl(1,2,0,0);
      tri[6]  = Cl(1,1,0,0)*Cl(0,0,0,0).real() + Cl(1,1,1,1)*Cl(1,1,0,0) + Cl(1,1,0,1)*Cl(0,1,0,0) + Cl(1,1,0,2)*Cl(0,2,0,0) + Cl(1,1,1,0)*Cl(1,0,0,0) + Cl(1,1,1,2)*Cl(1,2,0,0);
      tri[10] = Cl(1,2,0,0)*Cl(0,0,0,0).real() + Cl(1,2,1,2)*Cl(1,2,0,0) + Cl(1,2,0,1)*Cl(0,1,0,0) + Cl(1,2,0,2)*Cl(0,2,0,0) + Cl(1,2,1,0)*Cl(1,0,0,0) + Cl(1,2,1,1)*Cl(1,1,0,0);

      tri[2]  = Cl(0,2,0,1)*Cl(0,1,0,1).real() + Cl(0,2,0,2)*Cl(0,2,0,1) + Cl(0,2,0,0)*Cl(0,0,0,1) + Cl(0,2,1,0)*Cl(1,0,0,1) + Cl(0,2,1,1)*Cl(1,1,0,1) + Cl(0,2,1,2)*Cl(1,2,0,1);
      tri[4]  = Cl(1,0,0,1)*Cl(0,1,0,1).real() + Cl(1,0,1,0)*Cl(1,0,0,1) + Cl(1,0,0,0)*Cl(0,0,0,1) + Cl(1,0,0,2)*Cl(0,2,0,1) + Cl(1,0,1,1)*Cl(1,1,0,1) + Cl(1,0,1,2)*Cl(1,2,0,1);
      tri[7]  = Cl(1,1,0,1)*Cl(0,1,0,1).real() + Cl(1,1,1,1)*Cl(1,1,0,1) + Cl(1,1,0,0)*Cl(0,0,0,1) + Cl(1,1,0,2)*Cl(0,2,0,1) + Cl(1,1,1,0)*Cl(1,0,0,1) + Cl(1,1,1,2)*Cl(1,2,0,1);
      tri[11] = Cl(1,2,0,1)*Cl(0,1,0,1).real() + Cl(1,2,1,2)*Cl(1,2,0,1) + Cl(1,2,0,0)*Cl(0,0,0,1) + Cl(1,2,0,2)*Cl(0,2,0,1) + Cl(1,2,1,0)*Cl(1,0,0,1) + Cl(1,2,1,1)*Cl(1,1,0,1);

      tri[5]  = Cl(1,0,0,2)*Cl(0,2,0,2).real() + Cl(1,0,1,0)*Cl(1,0,0,2) + Cl(1,0,0,0)*Cl(0,0,0,2) + Cl(1,0,0,1)*Cl(0,1,0,2) + Cl(1,0,1,1)*Cl(1,1,0,2) + Cl(1,0,1,2)*Cl(1,2,0,2);
      tri[8]  = Cl(1,1,0,2)*Cl(0,2,0,2).real() + Cl(1,1,1,1)*Cl(1,1,0,2) + Cl(1,1,0,0)*Cl(0,0,0,2) + Cl(1,1,0,1)*Cl(0,1,0,2) + Cl(1,1,1,0)*Cl(1,0,0,2) + Cl(1,1,1,2)*Cl(1,2,0,2);
      tri[12] = Cl(1,2,0,2)*Cl(0,2,0,2).real() + Cl(1,2,1,2)*Cl(1,2,0,2) + Cl(1,2,0,0)*Cl(0,0,0,2) + Cl(1,2,0,1)*Cl(0,1,0,2) + Cl(1,2,1,0)*Cl(1,0,0,2) + Cl(1,2,1,1)*Cl(1,1,0,2);

      tri[9]  = Cl(1,1,1,0)*Cl(1,0,1,0).real() + Cl(1,1,1,1)*Cl(1,1,1,0) + Cl(1,1,0,0)*Cl(0,0,1,0) + Cl(1,1,0,1)*Cl(0,1,1,0) + Cl(1,1,0,2)*Cl(0,2,1,0) + Cl(1,1,1,2)*Cl(1,2,1,0);
      tri[13] = Cl(1,2,1,0)*Cl(1,0,1,0).real() + Cl(1,2,1,2)*Cl(1,2,1,0) + Cl(1,2,0,0)*Cl(0,0,1,0) + Cl(1,2,0,1)*Cl(0,1,1,0) + Cl(1,2,0,2)*Cl(0,2,1,0) + Cl(1,2,1,1)*Cl(1,1,1,0);
      tri[14] = Cl(1,2,1,1)*Cl(1,1,1,1).real() + Cl(1,2,1,2)*Cl(1,2,1,1) + Cl(1,2,0,0)*Cl(0,0,1,1) + Cl(1,2,0,1)*Cl(0,1,1,1) + Cl(1,2,0,2)*Cl(0,2,1,1) + Cl(1,2,1,0)*Cl(1,0,1,1);

      diag[0] = arg.mu*arg.mu + Cl(0,0,0,0).real()*Cl(0,0,0,0).real() + norm(Cl(0,1,0,0)) + norm(Cl(0,2,0,0)) + norm(Cl(1,0,0,0)) + norm(Cl(1,1,0,0)) + norm(Cl(1,2,0,0));
      diag[1] = arg.mu*arg.mu + Cl(0,1,0,1).real()*Cl(0,1,0,1).real() + norm(Cl(0,0,0,1)) + norm(Cl(0,2,0,1)) + norm(Cl(1,0,0,1)) + norm(Cl(1,1,0,1)) + norm(Cl(1,2,0,1));
      diag[2] = arg.mu*arg.mu + Cl(0,2,0,2).real()*Cl(0,2,0,2).real() + norm(Cl(0,0,0,2)) + norm(Cl(0,1,0,2)) + norm(Cl(1,0,0,2)) + norm(Cl(1,1,0,2)) + norm(Cl(1,2,0,2));
      diag[3] = arg.mu*arg.mu + Cl(1,0,1,0).real()*Cl(1,0,1,0).real() + norm(Cl(0,0,1,0)) + norm(Cl(0,1,1,0)) + norm(Cl(0,2,1,0)) + norm(Cl(1,1,1,0)) + norm(Cl(1,2,1,0));
      diag[4] = arg.mu*arg.mu + Cl(1,1,1,1).real()*Cl(1,1,1,1).real() + norm(Cl(0,0,1,1)) + norm(Cl(0,1,1,1)) + norm(Cl(0,2,1,1)) + norm(Cl(1,0,1,1)) + norm(Cl(1,2,1,1));
      diag[5] = arg.mu*arg.mu + Cl(1,2,1,2).real()*Cl(1,2,1,2).real() + norm(Cl(0,0,1,2)) + norm(Cl(0,1,1,2)) + norm(Cl(0,2,1,2)) + norm(Cl(1,0,1,2)) + norm(Cl(1,1,1,2));

      #undef Cl

      /*	INVERSION STARTS	*/

      for (int j=0; j<6; j++) {
        diag[j] = sqrt(diag[j]);
        tmp[j] = 1./diag[j];

        for (int k=j+1; k<6; k++) {
          int kj = k*(k-1)/2+j;
          tri[kj] *= tmp[j];
        }

        for(int k=j+1;k<6;k++){
          int kj=k*(k-1)/2+j;
          diag[k] -= (tri[kj] * conj(tri[kj])).real();
          for(int l=k+1;l<6;l++){
            int lj=l*(l-1)/2+j;
            int lk=l*(l-1)/2+k;
            tri[lk] -= tri[lj] * conj(tri[kj]);
          }
        }
      }

      /* Now use forward and backward substitution to construct inverse */
      complex<Float> v1[6];
      for (int k=0;k<6;k++) {
        for(int l=0;l<k;l++) v1[l] = complex<Float>(0.0, 0.0);

        /* Forward substitute */
        v1[k] = complex<Float>(tmp[k], 0.0);
        for(int l=k+1;l<6;l++){
          complex<Float> sum = complex<Float>(0.0, 0.0);
          for(int j=k;j<l;j++){
            int lj=l*(l-1)/2+j;
            sum -= tri[lj] * v1[j];
          }
          v1[l] = sum * tmp[l];
        }

        /* Backward substitute */
        v1[5] = v1[5] * tmp[5];
        for(int l=4;l>=k;l--){
          complex<Float> sum = v1[l];
          for(int j=l+1;j<6;j++){
            int jl=j*(j-1)/2+l;
            sum -= conj(tri[jl]) * v1[j];
          }
          v1[l] = sum * tmp[l];
        }

        /* Overwrite column k */
        diag[k] = v1[k].real();
        for(int l=k+1;l<6;l++){
          int lk=l*(l-1)/2+k;
          tri[lk] = v1[l];
        }
      }

      /*	Calculate the product for the current chiral block	*/

      //Then we calculate AV = Cinv UV, so  [AV = (C^2 + mu^2)^{-1} (Clover -/+ i mu)·Vector]
      //for in twisted-clover fermions, Cinv keeps (C^2 + mu^2)^{-1}

      for(int ic_c = 0; ic_c < coarseColor; ic_c++) {  // Coarse Color
	for (int j=0; j<(fineSpin/2)*fineColor; j++) {	// This won't work for anything different than fineColor = 3, fineSpin = 4
	  int s = j / fineColor, ic = j % fineColor;

	  arg.AV(parity, x_cb, s+2*ch, ic, ic_c) += diag[j] * arg.UV(parity, x_cb, s+2*ch, ic, ic_c);	// Diagonal clover

	  for (int k=0; k<j; k++) {
	    const int jk = j*(j-1)/2 + k;
	    const int s_col = k / fineColor, jc = k % fineColor;

	    arg.AV(parity, x_cb, s+2*ch, ic, ic_c) += tri[jk] * arg.UV(parity, x_cb, s_col+2*ch, jc, ic_c); // Off-diagonal
	  }

	  for (int k=j+1; k<(fineSpin/2)*fineColor; k++) {
	    int kj = k*(k-1)/2 + j;
	    int s_col = k / fineColor, jc = k % fineColor;

	    arg.AV(parity, x_cb, s+2*ch, ic, ic_c) += conj(tri[kj]) * arg.UV(parity, x_cb, s_col+2*ch, jc, ic_c); // Off-diagonal
	  }
	}
      }	// Coarse color
    } // Chirality
  }

  #endif // UGLY_DYNCLOV
#endif // DYNAMIC_CLOVER

  /**
     Calculates the matrix A V^{s,c'}(x) = \sum_c A^{c}(x) * V^{s,c}(x) for twisted-clover fermions
     Where: s = fine spin, c' = coarse color, c = fine color
  */
  template<typename Float, int fineSpin, int fineColor, int coarseColor, typename Arg>
  __device__ __host__ inline void computeTMCAV(Arg &arg, int parity, int x_cb) {

    complex<Float> mu(0.,arg.mu);

    for(int s = 0; s < fineSpin; s++) {
      for(int c = 0; c < fineColor; c++) {
	for(int v = 0; v < coarseColor; v++) {
	  arg.UV(parity,x_cb,s,c,v) = static_cast<Float>(0.0);
	  arg.AV(parity,x_cb,s,c,v) = static_cast<Float>(0.0);
	}
      }
    }

    //First we store in UV the product [(Clover -/+ i mu)·Vector]
    for(int s = 0; s < fineSpin; s++) {  //Fine Spin
      const int s_c = s/arg.spin_bs;

      //On the fine lattice, the clover field is chirally blocked, so loop over rows/columns
      //in the same chiral block.
      for(int s_col = s_c*arg.spin_bs; s_col < (s_c+1)*arg.spin_bs; s_col++) { //Loop over fine spin column

	for(int ic_c = 0; ic_c < coarseColor; ic_c++) {  //Coarse Color
	  for(int ic = 0; ic < fineColor; ic++) { //Fine Color rows of gauge field
	    for(int jc = 0; jc < fineColor; jc++) {  //Fine Color columns of gauge field
	      arg.UV(parity, x_cb, s, ic, ic_c) +=
		arg.C(0, parity, x_cb, s, s_col, ic, jc) * arg.V(parity, x_cb, s_col, jc, ic_c);
	    }  //Fine color columns
	  }  //Fine color rows
	} //Coarse color
      }
    } //Fine Spin

    for(int s = 0; s < fineSpin/2; s++) {  //Fine Spin
      for(int ic_c = 0; ic_c < coarseColor; ic_c++) {  //Coarse Color
	for(int ic = 0; ic < fineColor; ic++) { //Fine Color
	  arg.UV(parity, x_cb, s, ic, ic_c) -= mu * arg.V(parity, x_cb, s, ic, ic_c);
	}  //Fine color
      } //Coarse color
    } //Fine Spin

    for(int s = fineSpin/2; s < fineSpin; s++) {  //Fine Spin
      for(int ic_c = 0; ic_c < coarseColor; ic_c++) {  //Coarse Color
	for(int ic = 0; ic < fineColor; ic++) { //Fine Color
	  arg.UV(parity, x_cb, s, ic, ic_c) += mu * arg.V(parity, x_cb, s, ic, ic_c);
	}  //Fine color
      } //Coarse color
    } //Fine Spin

#ifndef	DYNAMIC_CLOVER
    //Then we calculate AV = Cinv UV, so  [AV = (C^2 + mu^2)^{-1} (Clover -/+ i mu)·Vector]
    //for in twisted-clover fermions, Cinv keeps (C^2 + mu^2)^{-1}
    for(int s = 0; s < fineSpin; s++) {  //Fine Spin
      const int s_c = s/arg.spin_bs;

      //On the fine lattice, the clover field is chirally blocked, so loop over rows/columns
      //in the same chiral block.
      for(int s_col = s_c*arg.spin_bs; s_col < (s_c+1)*arg.spin_bs; s_col++) { //Loop over fine spin column

	for(int ic_c = 0; ic_c < coarseColor; ic_c++) {  //Coarse Color
	  for(int ic = 0; ic < fineColor; ic++) { //Fine Color rows of gauge field
	    for(int jc = 0; jc < fineColor; jc++) {  //Fine Color columns of gauge field
	      arg.AV(parity, x_cb, s, ic, ic_c) +=
		arg.Cinv(0, parity, x_cb, s, s_col, ic, jc) * arg.UV(parity, x_cb, s_col, jc, ic_c);
	    }  //Fine color columns
	  }  //Fine color rows
	} //Coarse color
      }
    } //Fine Spin
#else
    applyInvClover<Float,fineSpin,fineColor,coarseColor,Arg>(arg, parity, x_cb);
#endif
  } // computeTMCAV

  template<typename Float, int fineSpin, int fineColor, int coarseColor, typename Arg>
  void ComputeTMCAVCPU(Arg &arg) {
    for (int parity=0; parity<2; parity++) {
      for (int x_cb=0; x_cb<arg.fineVolumeCB; x_cb++) {
	computeTMCAV<Float,fineSpin,fineColor,coarseColor,Arg>(arg, parity, x_cb);
      } // c/b volume
    }   // parity
  }

  template<typename Float, int fineSpin, int fineColor, int coarseColor, typename Arg>
  __global__ void ComputeTMCAVGPU(Arg arg) {
    int x_cb = blockDim.x*blockIdx.x + threadIdx.x;
    if (x_cb >= arg.fineVolumeCB) return;

    int parity = blockDim.y*blockIdx.y + threadIdx.y;
    computeTMCAV<Float,fineSpin,fineColor,coarseColor,Arg>(arg, parity, x_cb);
  }

  /**
     @brief Do a single (AV)^\dagger * UV product, where for preconditioned
     clover, AV correspond to the clover inverse multiplied by the
     packed null space vectors, else AV is simply the packed null
     space vectors.

     @param[out] vuv Result array
     @param[in,out] arg Arg storing the fields and parameters
     @param[in] Fine grid parity we're working on
     @param[in] x_cb Checkboarded x dimension
   */
  template <bool from_coarse, typename Float, int dim, QudaDirection dir, int fineSpin, int fineColor, int coarseSpin, int coarseColor, typename Arg>
    __device__ __host__ inline void multiplyVUV(complex<Float> vuv[], Arg &arg, int parity, int x_cb, int ic_c) {

    Gamma<Float, QUDA_DEGRAND_ROSSI_GAMMA_BASIS, dim> gamma;

    for (int i=0; i<coarseSpin*coarseSpin*coarseColor; i++) vuv[i] = 0.0;

    if (!from_coarse) { // fine grid is top level

      for(int s = 0; s < fineSpin; s++) { //Loop over fine spin

	//Spin part of the color matrix.  Will always consist
	//of two terms - diagonal and off-diagonal part of
	//P_mu = (1+/-\gamma_mu)

	int s_c_row = s/arg.spin_bs; //Coarse spin row index

	//Use Gamma to calculate off-diagonal coupling and
	//column index.  Diagonal coupling is always 1.
	// If computing the backwards (forwards) direction link then
	// we desire the positive (negative) projector

	int s_col;
	complex<Float> coupling = gamma.getrowelem(s, s_col);
	int s_c_col = s_col/arg.spin_bs;

	{ //for(int ic_c = 0; ic_c < coarseColor; ic_c++) { //Coarse Color row
	  for(int jc_c = 0; jc_c < coarseColor; jc_c++) { //Coarse Color column
	    for(int ic = 0; ic < fineColor; ic++) { //Sum over fine color
	      if (dir == QUDA_BACKWARDS) {
		// here UV is really UAV
		//Diagonal Spin
		//		vuv[((s_c_row*coarseSpin+s_c_row)*coarseColor+ic_c)*coarseColor+jc_c] +=
		vuv[(s_c_row*coarseSpin+s_c_row)*coarseColor+jc_c] +=
		  conj(arg.V(parity, x_cb, s, ic, ic_c)) * arg.UV(parity, x_cb, s, ic, jc_c);

		//Off-diagonal Spin (backward link / positive projector applied)
		//vuv[((s_c_row*coarseSpin+s_c_col)*coarseColor+ic_c)*coarseColor+jc_c] +=
		vuv[(s_c_row*coarseSpin+s_c_col)*coarseColor+jc_c] +=
		  coupling * conj(arg.V(parity, x_cb, s, ic, ic_c)) * arg.UV(parity, x_cb, s_col, ic, jc_c);
	      } else {
		//Diagonal Spin
		//vuv[((s_c_row*coarseSpin+s_c_row)*coarseColor+ic_c)*coarseColor+jc_c] +=
		vuv[(s_c_row*coarseSpin+s_c_row)*coarseColor+jc_c] +=
		  conj(arg.AV(parity, x_cb, s, ic, ic_c)) * arg.UV(parity, x_cb, s, ic, jc_c);

		//Off-diagonal Spin (forward link / negative projector applied)
		//vuv[((s_c_row*coarseSpin+s_c_col)*coarseColor+ic_c)*coarseColor+jc_c] -=
		vuv[(s_c_row*coarseSpin+s_c_col)*coarseColor+jc_c] -=
		  coupling * conj(arg.AV(parity, x_cb, s, ic, ic_c)) * arg.UV(parity, x_cb, s_col, ic, jc_c);
	      }
	    } //Fine color
	  } //Coarse Color column
	} //Coarse Color row 
      }

    } else { // fine grid operator is a coarse operator

      for (int s_col=0; s_col<fineSpin; s_col++) { // which chiral block
	for (int s = 0; s < fineSpin; s++) {
	  //for(int ic_c = 0; ic_c < coarseColor; ic_c++) { //Coarse Color row
	    for(int jc_c = 0; jc_c < coarseColor; jc_c++) { //Coarse Color column
	      for(int ic = 0; ic < fineColor; ic++) { //Sum over fine color
		//vuv[((s*coarseSpin+s_col)*coarseColor+ic_)c*coarseColo+jc_c] +=
		vuv[(s*coarseSpin+s_col)*coarseColor+jc_c] +=
		  conj(arg.AV(parity, x_cb, s, ic, ic_c)) * arg.UV(parity, x_cb, s_col*fineSpin+s, ic, jc_c);
	      } //Fine color
	    } //Coarse Color column
	      //} //Coarse Color row
	} //Fine spin
      }

    } // from_coarse

  }

  template<bool from_coarse, typename Float, int dim, QudaDirection dir, int fineSpin, int fineColor, int coarseSpin, int coarseColor, typename Arg>
    __device__ __host__ void computeVUV(Arg &arg, int parity, int x_cb, int c_row) {

    const int nDim = 4;
    int coord[QUDA_MAX_DIM];
    int coord_coarse[QUDA_MAX_DIM];
    int coarse_size = 1;
    for(int d = 0; d<nDim; d++) coarse_size *= arg.xc_size[d];

    getCoords(coord, x_cb, arg.x_size, parity);
    for(int d = 0; d < nDim; d++) coord_coarse[d] = coord[d]/arg.geo_bs[d];

    //Check to see if we are on the edge of a block.  If adjacent site
    //is in same block, M = X, else M = Y
    const bool isDiagonal = ((coord[dim]+1)%arg.x_size[dim])/arg.geo_bs[dim] == coord_coarse[dim] ? true : false;

    // store the forward and backward clover contributions separately for now since they can't be added coeherently easily
    auto &M = isDiagonal ? (dir == QUDA_BACKWARDS ? arg.X : arg.Xinv) : arg.Y;
    const int dim_index = isDiagonal ? 0 : (dir == QUDA_BACKWARDS ? dim : dim + 4);

    int coarse_parity = 0;
    for (int d=0; d<nDim; d++) coarse_parity += coord_coarse[d];
    coarse_parity &= 1;
    coord_coarse[0] /= 2;
    int coarse_x_cb = ((coord_coarse[3]*arg.xc_size[2]+coord_coarse[2])*arg.xc_size[1]+coord_coarse[1])*(arg.xc_size[0]/2) + coord_coarse[0];
    coord[0] /= 2;

    //complex<Float> vuv[coarseSpin*coarseSpin*coarseColor*coarseColor];
    complex<Float> vuv[coarseSpin*coarseSpin*coarseColor];
    multiplyVUV<from_coarse,Float,dim,dir,fineSpin,fineColor,coarseSpin,coarseColor,Arg>(vuv, arg, parity, x_cb, c_row);

    for (int s_row = 0; s_row < coarseSpin; s_row++) { // Chiral row block
      for (int s_col = 0; s_col < coarseSpin; s_col++) { // Chiral column block
	//	for(int c_row = 0; c_row < coarseColor; c_row++) { // Coarse Color row
	  for(int c_col = 0; c_col < coarseColor; c_col++) { // Coarse Color column
	    M.atomicAdd(dim_index,coarse_parity,coarse_x_cb,s_row,s_col,c_row,c_col,
			vuv[(s_row*coarseSpin+s_col)*coarseColor+c_col]);
	  } //Coarse Color column
	  //} //Coarse Color row
      }
    }

  }

  template<bool from_coarse, typename Float, int dim, QudaDirection dir, int fineSpin, int fineColor, int coarseSpin, int coarseColor, typename Arg>
  void ComputeVUVCPU(Arg arg) {
    for (int parity=0; parity<2; parity++) {
      for (int x_cb=0; x_cb<arg.fineVolumeCB; x_cb++) { // Loop over fine volume
	for (int c_row=0; c_row<coarseColor; c_row++)
	  computeVUV<from_coarse,Float,dim,dir,fineSpin,fineColor,coarseSpin,coarseColor,Arg>(arg, parity, x_cb, c_row);
      } // c/b volume
    } // parity
  }

  template<bool from_coarse, typename Float, int dim, QudaDirection dir, int fineSpin, int fineColor, int coarseSpin, int coarseColor, typename Arg>
  __global__ void ComputeVUVGPU(Arg arg) {
    int x_cb = blockDim.x*blockIdx.x + threadIdx.x;
    if (x_cb >= arg.fineVolumeCB) return;

    int parity = blockDim.y*blockIdx.y + threadIdx.y;
    int c_row = blockDim.z*blockIdx.z + threadIdx.z; // coarse color
    if (c_row >= coarseColor) return;
    computeVUV<from_coarse,Float,dim,dir,fineSpin,fineColor,coarseSpin,coarseColor,Arg>(arg, parity, x_cb, c_row);
  }

  /**
   * Compute the forward links from backwards links by flipping the
   * sign of the spin projector
   */
  template<typename Float, int nSpin, int nColor, typename Arg>
  __device__ __host__ void computeYreverse(Arg &arg, int parity, int x_cb) {
    auto &Y = arg.Y;

    for (int d=0; d<4; d++) {
      for(int s_row = 0; s_row < nSpin; s_row++) { //Spin row
	for(int s_col = 0; s_col < nSpin; s_col++) { //Spin column

	  const Float sign = (s_row == s_col) ? static_cast<Float>(1.0) : static_cast<Float>(-1.0);

	  for(int ic_c = 0; ic_c < nColor; ic_c++) { //Color row
	    for(int jc_c = 0; jc_c < nColor; jc_c++) { //Color column
	      Y(d+4,parity,x_cb,s_row,s_col,ic_c,jc_c) = sign*Y(d,parity,x_cb,s_row,s_col,ic_c,jc_c);
	    } //Color column
	  } //Color row
	} //Spin column
      } //Spin row

    } // dimension

  }

  template<typename Float, int nSpin, int nColor, typename Arg>
  void ComputeYReverseCPU(Arg &arg) {
    for (int parity=0; parity<2; parity++) {
      for (int x_cb=0; x_cb<arg.coarseVolumeCB; x_cb++) {
	computeYreverse<Float,nSpin,nColor,Arg>(arg, parity, x_cb);
      } // c/b volume
    } // parity
  }

  template<typename Float, int nSpin, int nColor, typename Arg>
  __global__ void ComputeYReverseGPU(Arg arg) {
    int x_cb = blockDim.x*blockIdx.x + threadIdx.x;
    if (x_cb >= arg.coarseVolumeCB) return;

    int parity = blockDim.y*blockIdx.y + threadIdx.y;
    computeYreverse<Float,nSpin,nColor,Arg>(arg, parity, x_cb);
  }

  /**
   * Adds the reverse links to the coarse local term, which is just
   * the conjugate of the existing coarse local term but with
   * plus/minus signs for off-diagonal spin components so multiply by
   * the appropriate factor of -kappa.
   *
  */
  template<bool bidirectional, typename Float, int nSpin, int nColor, typename Arg>
  __device__ __host__ void computeCoarseLocal(Arg &arg, int parity, int x_cb)
  {
    complex<Float> Xlocal[nSpin*nSpin*nColor*nColor];

    for(int s_row = 0; s_row < nSpin; s_row++) { //Spin row
      for(int s_col = 0; s_col < nSpin; s_col++) { //Spin column

	//Copy the Hermitian conjugate term to temp location
	for(int ic_c = 0; ic_c < nColor; ic_c++) { //Color row
	  for(int jc_c = 0; jc_c < nColor; jc_c++) { //Color column
	    //Flip s_col, s_row on the rhs because of Hermitian conjugation.  Color part left untransposed.
	    Xlocal[((nSpin*s_col+s_row)*nColor+ic_c)*nColor+jc_c] = arg.X(0,parity,x_cb,s_row, s_col, ic_c, jc_c);
	  }
	}
      }
    }

    for(int s_row = 0; s_row < nSpin; s_row++) { //Spin row
      for(int s_col = 0; s_col < nSpin; s_col++) { //Spin column

	const Float sign = (s_row == s_col) ? static_cast<Float>(1.0) : static_cast<Float>(-1.0);

	for(int ic_c = 0; ic_c < nColor; ic_c++) { //Color row
	  for(int jc_c = 0; jc_c < nColor; jc_c++) { //Color column
	    if (bidirectional) {
	      // here we have forwards links in Xinv and backwards links in X
	      arg.X(0,parity,x_cb,s_row,s_col,ic_c,jc_c) =
		-arg.kappa*(arg.Xinv(0,parity,x_cb,s_row,s_col,ic_c,jc_c)
			    +conj(Xlocal[((nSpin*s_row+s_col)*nColor+jc_c)*nColor+ic_c]));
	    } else {
	      // here we have just backwards links
	      arg.X(0,parity,x_cb,s_row,s_col,ic_c,jc_c) =
		-arg.kappa*(sign*arg.X(0,parity,x_cb,s_row,s_col,ic_c,jc_c)
			    +conj(Xlocal[((nSpin*s_row+s_col)*nColor+jc_c)*nColor+ic_c]));
	    }
	  } //Color column
	} //Color row
      } //Spin column
    } //Spin row

  }

  template<bool bidirectional, typename Float, int nSpin, int nColor, typename Arg>
  void ComputeCoarseLocalCPU(Arg &arg) {
    for (int parity=0; parity<2; parity++) {
      for (int x_cb=0; x_cb<arg.coarseVolumeCB; x_cb++) {
	computeCoarseLocal<bidirectional,Float,nSpin,nColor,Arg>(arg, parity, x_cb);
      } // c/b volume
    } // parity
  }

  template<bool bidirectional, typename Float, int nSpin, int nColor, typename Arg>
  __global__ void ComputeCoarseLocalGPU(Arg arg) {
    int x_cb = blockDim.x*blockIdx.x + threadIdx.x;
    if (x_cb >= arg.coarseVolumeCB) return;

    int parity = blockDim.y*blockIdx.y + threadIdx.y;
    computeCoarseLocal<bidirectional,Float,nSpin,nColor,Arg>(arg, parity, x_cb);
  }


  template<bool from_coarse, typename Float, int fineSpin, int coarseSpin, int fineColor, int coarseColor, typename Arg>
  __device__ __host__ void computeCoarseClover(Arg &arg, int parity, int x_cb, int ic_c) {

    const int nDim = 4;

    int coord[QUDA_MAX_DIM];
    int coord_coarse[QUDA_MAX_DIM];
    int coarse_size = 1;
    for(int d = 0; d<nDim; d++) coarse_size *= arg.xc_size[d];

    getCoords(coord, x_cb, arg.x_size, parity);
    for (int d=0; d<nDim; d++) coord_coarse[d] = coord[d]/arg.geo_bs[d];

    int coarse_parity = 0;
    for (int d=0; d<nDim; d++) coarse_parity += coord_coarse[d];
    coarse_parity &= 1;
    coord_coarse[0] /= 2;
    int coarse_x_cb = ((coord_coarse[3]*arg.xc_size[2]+coord_coarse[2])*arg.xc_size[1]+coord_coarse[1])*(arg.xc_size[0]/2) + coord_coarse[0];

    coord[0] /= 2;

    complex<Float> X[coarseSpin*coarseSpin*coarseColor];
    for (int i=0; i<coarseSpin*coarseSpin*coarseColor; i++) X[i] = 0.0;

    if (!from_coarse) {
      //If Nspin = 4, then the clover term has structure C_{\mu\nu} = \gamma_{\mu\nu}C^{\mu\nu}
      for(int s = 0; s < fineSpin; s++) { //Loop over fine spin row
	int s_c = s/arg.spin_bs;
	//On the fine lattice, the clover field is chirally blocked, so loop over rows/columns
	//in the same chiral block.
	for(int s_col = s_c*arg.spin_bs; s_col < (s_c+1)*arg.spin_bs; s_col++) { //Loop over fine spin column
	  //for(int ic_c = 0; ic_c < coarseColor; ic_c++) { //Coarse Color row
	    for(int jc_c = 0; jc_c < coarseColor; jc_c++) { //Coarse Color column
	      for(int ic = 0; ic < fineColor; ic++) { //Sum over fine color row
		for(int jc = 0; jc < fineColor; jc++) {  //Sum over fine color column
		  X[ (s_c*coarseSpin + s_c)*coarseColor + jc_c] +=
		    conj(arg.V(parity, x_cb, s, ic, ic_c)) * arg.C(0, parity, x_cb, s, s_col, ic, jc) * arg.V(parity, x_cb, s_col, jc, jc_c);
		} //Fine color column
	      }  //Fine color row
	    } //Coarse Color column
	    //} //Coarse Color row
	}  //Fine spin column
      } //Fine spin
    } else {
      //If Nspin != 4, then spin structure is a dense matrix and there is now spin aggregation
      //N.B. assumes that no further spin blocking is done in this case.
      for(int s = 0; s < fineSpin; s++) { //Loop over spin row
	for(int s_col = 0; s_col < fineSpin; s_col++) { //Loop over spin column
	  //for(int ic_c = 0; ic_c < coarseColor; ic_c++) { //Coarse Color row
	    for(int jc_c = 0; jc_c <coarseColor; jc_c++) { //Coarse Color column
	      for(int ic = 0; ic < fineColor; ic++) { //Sum over fine color row
		for(int jc = 0; jc < fineColor; jc++) {  //Sum over fine color column
		  X[ (s*coarseSpin + s_col)*coarseColor + jc_c] +=
		    conj(arg.V(parity, x_cb, s, ic, ic_c)) * arg.C(0, parity, x_cb, s, s_col, ic, jc) * arg.V(parity, x_cb, s_col, jc, jc_c);
		} //Fine color column
	      }  //Fine color row
	    } //Coarse Color column
	    //} //Coarse Color row
	}  //Fine spin column
      } //Fine spin
    }

    for (int si = 0; si < coarseSpin; si++) {
      for (int sj = 0; sj < coarseSpin; sj++) {
	//for (int ic = 0; ic < coarseColor; ic++) {
	  for (int jc = 0; jc < coarseColor; jc++) {
	    arg.X.atomicAdd(0,coarse_parity,coarse_x_cb,si,sj,ic_c,jc,X[(si*coarseSpin+sj)*coarseColor+jc]);
	  }
	  //}
      }
    }

  }

  template <bool from_coarse, typename Float, int fineSpin, int coarseSpin, int fineColor, int coarseColor, typename Arg>
  void ComputeCoarseCloverCPU(Arg &arg) {
    for (int parity=0; parity<2; parity++) {
      for (int x_cb=0; x_cb<arg.fineVolumeCB; x_cb++) {
	for (int ic_c=0; ic_c<coarseColor; ic_c++) {
	  computeCoarseClover<from_coarse,Float,fineSpin,coarseSpin,fineColor,coarseColor>(arg, parity, x_cb, ic_c);
	}
      } // c/b volume
    } // parity
  }

  template <bool from_coarse, typename Float, int fineSpin, int coarseSpin, int fineColor, int coarseColor, typename Arg>
  __global__ void ComputeCoarseCloverGPU(Arg arg) {
    int x_cb = blockDim.x*blockIdx.x + threadIdx.x;
    if (x_cb >= arg.fineVolumeCB) return;
    int parity = blockDim.y*blockIdx.y + threadIdx.y;
    int ic_c = blockDim.z*blockIdx.z + threadIdx.z; // coarse color
    if (ic_c >= coarseColor) return;
    computeCoarseClover<from_coarse,Float,fineSpin,coarseSpin,fineColor,coarseColor>(arg, parity, x_cb, ic_c);
  }



  //Adds the identity matrix to the coarse local term.
  template<typename Float, int nSpin, int nColor, typename Arg>
  void AddCoarseDiagonalCPU(Arg &arg) {
    for (int parity=0; parity<2; parity++) {
      for (int x_cb=0; x_cb<arg.coarseVolumeCB; x_cb++) {
        for(int s = 0; s < nSpin; s++) { //Spin
         for(int c = 0; c < nColor; c++) { //Color
	   arg.X(0,parity,x_cb,s,s,c,c) += static_cast<Float>(1.0);
         } //Color
        } //Spin
      } // x_cb
    } //parity
   }


  //Adds the identity matrix to the coarse local term.
  template<typename Float, int nSpin, int nColor, typename Arg>
  __global__ void AddCoarseDiagonalGPU(Arg arg) {
    int x_cb = blockDim.x*blockIdx.x + threadIdx.x;
    if (x_cb >= arg.coarseVolumeCB) return;
    int parity = blockDim.y*blockIdx.y + threadIdx.y;

    for(int s = 0; s < nSpin; s++) { //Spin
      for(int c = 0; c < nColor; c++) { //Color
	arg.X(0,parity,x_cb,s,s,c,c) += static_cast<Float>(1.0);
      } //Color
    } //Spin
   }

  //Adds the twisted-mass term to the coarse local term.
  template<typename Float, int nSpin, int nColor, typename Arg>
  void AddCoarseTmDiagonalCPU(Arg &arg) {

    const complex<Float> mu(0., arg.mu*arg.mu_factor);

    for (int parity=0; parity<2; parity++) {
      for (int x_cb=0; x_cb<arg.coarseVolumeCB; x_cb++) {
	for(int s = 0; s < nSpin/2; s++) { //Spin
          for(int c = 0; c < nColor; c++) { //Color
            arg.X(0,parity,x_cb,s,s,c,c) += mu;
          } //Color
	} //Spin
	for(int s = nSpin/2; s < nSpin; s++) { //Spin
          for(int c = 0; c < nColor; c++) { //Color
            arg.X(0,parity,x_cb,s,s,c,c) -= mu;
          } //Color
	} //Spin
      } // x_cb
    } //parity
  }

  //Adds the twisted-mass term to the coarse local term.
  template<typename Float, int nSpin, int nColor, typename Arg>
  __global__ void AddCoarseTmDiagonalGPU(Arg arg) {
    int x_cb = blockDim.x*blockIdx.x + threadIdx.x;
    if (x_cb >= arg.coarseVolumeCB) return;
    int parity = blockDim.y*blockIdx.y + threadIdx.y;

    const complex<Float> mu(0., arg.mu*arg.mu_factor);

    for(int s = 0; s < nSpin/2; s++) { //Spin
      for(int ic_c = 0; ic_c < nColor; ic_c++) { //Color
       arg.X(0,parity,x_cb,s,s,ic_c,ic_c) += mu;
      } //Color
    } //Spin
    for(int s = nSpin/2; s < nSpin; s++) { //Spin
      for(int ic_c = 0; ic_c < nColor; ic_c++) { //Color
       arg.X(0,parity,x_cb,s,s,ic_c,ic_c) -= mu;
      } //Color
    } //Spin
   }

  enum ComputeType {
    COMPUTE_UV,
    COMPUTE_AV,
    COMPUTE_TMAV,
    COMPUTE_TMCAV,
    COMPUTE_VUV,
    COMPUTE_COARSE_CLOVER,
    COMPUTE_REVERSE_Y,
    COMPUTE_COARSE_LOCAL,
    COMPUTE_DIAGONAL,
    COMPUTE_TMDIAGONAL,
    COMPUTE_INVALID
  };

  template <bool from_coarse, typename Float, int fineSpin,
	    int fineColor, int coarseSpin, int coarseColor, typename Arg>
  class CalculateY : public TunableVectorYZ {

  protected:
    Arg &arg;
    const ColorSpinorField &meta;
    GaugeField &Y;
    GaugeField &X;
    GaugeField &Xinv;

    int dim;
    QudaDirection dir;
    ComputeType type;
    bool bidirectional;

    long long flops() const
    {
      long long flops_ = 0;
      switch (type) {
      case COMPUTE_UV:
	// when fine operator is coarse take into account that the link matrix has spin dependence
	flops_ = 2l * arg.fineVolumeCB * 8 * fineSpin * coarseColor * fineColor * fineColor * (!from_coarse ? 1 : fineSpin);
	break;
      case COMPUTE_AV:
      case COMPUTE_TMAV:
	// # chiral blocks * size of chiral block * number of null space vectors
	flops_ = 2l * arg.fineVolumeCB * 8 * (fineSpin/2) * (fineSpin/2) * (fineSpin/2) * fineColor * fineColor * coarseColor;
	break;
      case COMPUTE_TMCAV:
	// # Twice chiral blocks * size of chiral block * number of null space vectors
	flops_ = 4l * arg.fineVolumeCB * 8 * (fineSpin/2) * (fineSpin/2) * (fineSpin/2) * fineColor * fineColor * coarseColor;
	break;
      case COMPUTE_VUV:
	// when the fine operator is truly fine the VUV multiplication is block sparse which halves the number of operations
	flops_ = 2l * arg.fineVolumeCB * 8 * fineSpin * fineSpin * coarseColor * coarseColor * fineColor / (!from_coarse ? coarseSpin : 1);
	break;
      case COMPUTE_COARSE_CLOVER:
	// when the fine operator is truly fine the clover multiplication is block sparse which halves the number of operations
	flops_ = 2l * arg.fineVolumeCB * 8 * fineSpin * fineSpin * coarseColor * coarseColor * fineColor * fineColor / (!from_coarse ? coarseSpin : 1);
	break;
      case COMPUTE_REVERSE_Y:
	// no floating point operations
	flops_ = 0;
	break;
      case COMPUTE_COARSE_LOCAL:
	// complex addition over all components
	flops_ = 2l * arg.coarseVolumeCB*coarseSpin*coarseSpin*coarseColor*coarseColor*2;
	break;
      case COMPUTE_DIAGONAL:
      case COMPUTE_TMDIAGONAL:
	// read addition on the diagonal
	flops_ = 2l * arg.coarseVolumeCB*coarseSpin*coarseColor;
	break;
      default:
	errorQuda("Undefined compute type %d", type);
      }
      // 2 from parity, 8 from complex
      return flops_;
    }
    long long bytes() const
    {
      long long bytes_ = 0;
      switch (type) {
      case COMPUTE_UV:
	bytes_ = arg.UV.Bytes() + arg.V.Bytes() + 2*arg.U.Bytes()*coarseColor;
	break;
      case COMPUTE_AV:
	bytes_ = arg.AV.Bytes() + arg.V.Bytes() + 2*arg.C.Bytes();
	break;
      case COMPUTE_TMAV:
	bytes_ = arg.AV.Bytes() + arg.V.Bytes();
	break;
      case COMPUTE_TMCAV:
	bytes_ = arg.AV.Bytes() + arg.V.Bytes() + arg.UV.Bytes() + 4*arg.C.Bytes(); // Two clover terms and more temporary storage
	break;
      case COMPUTE_VUV:
	bytes_ = arg.UV.Bytes() + arg.V.Bytes();
	break;
      case COMPUTE_COARSE_CLOVER:
	bytes_ = 2*arg.X.Bytes() + 2*arg.C.Bytes() + arg.V.Bytes(); // 2 from parity
	break;
      case COMPUTE_REVERSE_Y:
	bytes_ = 4*2*2*arg.Y.Bytes(); // 4 from direction, 2 from i/o, 2 from parity
      case COMPUTE_COARSE_LOCAL:
      case COMPUTE_DIAGONAL:
      case COMPUTE_TMDIAGONAL:
	bytes_ = 2*2*arg.X.Bytes(); // 2 from i/o, 2 from parity
	break;
      default:
	errorQuda("Undefined compute type %d", type);
      }
      return bytes_;
    }

    unsigned int minThreads() const {
      unsigned int threads = 0;
      switch (type) {
      case COMPUTE_UV:
      case COMPUTE_AV:
      case COMPUTE_TMAV:
      case COMPUTE_TMCAV:
      case COMPUTE_VUV:
      case COMPUTE_COARSE_CLOVER:
	threads = arg.fineVolumeCB;
	break;
      case COMPUTE_REVERSE_Y:
      case COMPUTE_COARSE_LOCAL:
      case COMPUTE_DIAGONAL:
      case COMPUTE_TMDIAGONAL:
	threads = arg.coarseVolumeCB;
	break;
      default:
	errorQuda("Undefined compute type %d", type);
      }
      return threads;
    }

    bool tuneGridDim() const { return false; } // don't tune the grid dimension

  public:
    CalculateY(Arg &arg, QudaDiracType dirac, const ColorSpinorField &meta, GaugeField &Y, GaugeField &X, GaugeField &Xinv)
      : TunableVectorYZ(2,1), arg(arg), type(COMPUTE_INVALID),
	bidirectional(dirac==QUDA_CLOVERPC_DIRAC || dirac==QUDA_COARSEPC_DIRAC || dirac==QUDA_TWISTED_MASSPC_DIRAC || dirac==QUDA_TWISTED_CLOVERPC_DIRAC ||  bidirectional_debug),
	meta(meta), Y(Y), X(X), Xinv(Xinv), dim(0), dir(QUDA_BACKWARDS)
    {
      strcpy(aux, meta.AuxString());
      strcat(aux,comm_dim_partitioned_string());
    }
    virtual ~CalculateY() { }

    void apply(const cudaStream_t &stream) {
      TuneParam tp = tuneLaunch(*this, getTuning(), QUDA_VERBOSE);

      if (meta.Location() == QUDA_CPU_FIELD_LOCATION) {

	if (type == COMPUTE_UV) {

	  if (dir == QUDA_BACKWARDS) {
	    if      (dim==0) ComputeUVCPU<from_coarse,Float,0,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	    else if (dim==1) ComputeUVCPU<from_coarse,Float,1,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	    else if (dim==2) ComputeUVCPU<from_coarse,Float,2,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	    else if (dim==3) ComputeUVCPU<from_coarse,Float,3,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	  } else if (dir == QUDA_FORWARDS) {
	    if      (dim==0) ComputeUVCPU<from_coarse,Float,0,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	    else if (dim==1) ComputeUVCPU<from_coarse,Float,1,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	    else if (dim==2) ComputeUVCPU<from_coarse,Float,2,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	    else if (dim==3) ComputeUVCPU<from_coarse,Float,3,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	  } else {
	    errorQuda("Undefined direction %d", dir);
	  }

	} else if (type == COMPUTE_AV) {

	  if (from_coarse) errorQuda("ComputeAV should only be called from the fine grid");
	  ComputeAVCPU<Float,fineSpin,fineColor,coarseColor>(arg);

	} else if (type == COMPUTE_TMAV) {

	  if (from_coarse) errorQuda("ComputeTMAV should only be called from the fine grid");
	  ComputeTMAVCPU<Float,fineSpin,fineColor,coarseColor>(arg);

	} else if (type == COMPUTE_TMCAV) {

	  if (from_coarse) errorQuda("ComputeTMCAV should only be called from the fine grid");
	  ComputeTMCAVCPU<Float,fineSpin,fineColor,coarseColor>(arg);

	} else if (type == COMPUTE_VUV) {

	  if (dir == QUDA_BACKWARDS) {
	    if      (dim==0) ComputeVUVCPU<from_coarse,Float,0,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	    else if (dim==1) ComputeVUVCPU<from_coarse,Float,1,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	    else if (dim==2) ComputeVUVCPU<from_coarse,Float,2,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	    else if (dim==3) ComputeVUVCPU<from_coarse,Float,3,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	  } else if (dir == QUDA_FORWARDS) {
	    if      (dim==0) ComputeVUVCPU<from_coarse,Float,0,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	    else if (dim==1) ComputeVUVCPU<from_coarse,Float,1,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	    else if (dim==2) ComputeVUVCPU<from_coarse,Float,2,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	    else if (dim==3) ComputeVUVCPU<from_coarse,Float,3,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor>(arg);
	  } else {
	    errorQuda("Undefined direction %d", dir);
	  }

	} else if (type == COMPUTE_COARSE_CLOVER) {

	  ComputeCoarseCloverCPU<from_coarse,Float,fineSpin,coarseSpin,fineColor,coarseColor>(arg);

	} else if (type == COMPUTE_REVERSE_Y) {

	  ComputeYReverseCPU<Float,coarseSpin,coarseColor>(arg);

	} else if (type == COMPUTE_COARSE_LOCAL) {

	  if (bidirectional) ComputeCoarseLocalCPU<true,Float,coarseSpin,coarseColor>(arg);
	  else ComputeCoarseLocalCPU<false,Float,coarseSpin,coarseColor>(arg);

	} else if (type == COMPUTE_DIAGONAL) {

	  AddCoarseDiagonalCPU<Float,coarseSpin,coarseColor>(arg);

	} else if (type == COMPUTE_TMDIAGONAL) {

          AddCoarseTmDiagonalCPU<Float,coarseSpin,coarseColor>(arg);

	} else {
	  errorQuda("Undefined compute type %d", type);
	}
      } else {

	if (type == COMPUTE_UV) {

	  if (dir == QUDA_BACKWARDS) {
	    if      (dim==0) ComputeUVGPU<from_coarse,Float,0,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	    else if (dim==1) ComputeUVGPU<from_coarse,Float,1,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	    else if (dim==2) ComputeUVGPU<from_coarse,Float,2,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	    else if (dim==3) ComputeUVGPU<from_coarse,Float,3,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	  } else if (dir == QUDA_FORWARDS) {
	    if      (dim==0) ComputeUVGPU<from_coarse,Float,0,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	    else if (dim==1) ComputeUVGPU<from_coarse,Float,1,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	    else if (dim==2) ComputeUVGPU<from_coarse,Float,2,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	    else if (dim==3) ComputeUVGPU<from_coarse,Float,3,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	  } else {
	    errorQuda("Undefined direction %d", dir);
	  }

	} else if (type == COMPUTE_AV) {

	  if (from_coarse) errorQuda("ComputeAV should only be called from the fine grid");
	  ComputeAVGPU<Float,fineSpin,fineColor,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);

	} else if (type == COMPUTE_TMAV) {

	  if (from_coarse) errorQuda("ComputeTMAV should only be called from the fine grid");
	  ComputeTMAVGPU<Float,fineSpin,fineColor,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);

	} else if (type == COMPUTE_TMCAV) {

	  if (from_coarse) errorQuda("ComputeTMCAV should only be called from the fine grid");
	  ComputeTMCAVGPU<Float,fineSpin,fineColor,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);

	} else if (type == COMPUTE_VUV) {

	  if (dir == QUDA_BACKWARDS) {
	    if      (dim==0) ComputeVUVGPU<from_coarse,Float,0,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	    else if (dim==1) ComputeVUVGPU<from_coarse,Float,1,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	    else if (dim==2) ComputeVUVGPU<from_coarse,Float,2,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	    else if (dim==3) ComputeVUVGPU<from_coarse,Float,3,QUDA_BACKWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	  } else if (dir == QUDA_FORWARDS) {
	    if      (dim==0) ComputeVUVGPU<from_coarse,Float,0,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	    else if (dim==1) ComputeVUVGPU<from_coarse,Float,1,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	    else if (dim==2) ComputeVUVGPU<from_coarse,Float,2,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	    else if (dim==3) ComputeVUVGPU<from_coarse,Float,3,QUDA_FORWARDS,fineSpin,fineColor,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	  } else {
	    errorQuda("Undefined direction %d", dir);
	  }

	} else if (type == COMPUTE_COARSE_CLOVER) {

	  ComputeCoarseCloverGPU<from_coarse,Float,fineSpin,coarseSpin,fineColor,coarseColor>
	    <<<tp.grid,tp.block,tp.shared_bytes>>>(arg);

	} else if (type == COMPUTE_REVERSE_Y) {

	  ComputeYReverseGPU<Float,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);

	} else if (type == COMPUTE_COARSE_LOCAL) {

	  if (bidirectional) ComputeCoarseLocalGPU<true,Float,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
	  else ComputeCoarseLocalGPU<false,Float,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);

	} else if (type == COMPUTE_DIAGONAL) {

	  AddCoarseDiagonalGPU<Float,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);

	} else if (type == COMPUTE_TMDIAGONAL) {

          AddCoarseTmDiagonalGPU<Float,coarseSpin,coarseColor><<<tp.grid,tp.block,tp.shared_bytes>>>(arg);

	} else {
	  errorQuda("Undefined compute type %d", type);
	}
      }
    }

    /**
       Set which dimension we are working on (where applicable)
    */
    void setDimension(int dim_) { dim = dim_; }

    /**
       Set which dimension we are working on (where applicable)
    */
    void setDirection(QudaDirection dir_) { dir = dir_; }

    /**
       Set which computation we are doing
     */
    void setComputeType(ComputeType type_) {
      type = type_;
      switch(type) {
      case COMPUTE_UV:
      case COMPUTE_AV:
      case COMPUTE_TMAV:
      case COMPUTE_VUV:
      case COMPUTE_COARSE_CLOVER:
	resizeVector(2,coarseColor);
	break;
      default:
	resizeVector(2,1);
	break;
      }
    }

    bool advanceTuneParam(TuneParam &param) const {
      if (meta.Location() == QUDA_CUDA_FIELD_LOCATION) return Tunable::advanceTuneParam(param);
      else return false;
    }

    TuneKey tuneKey() const {
      char Aux[TuneKey::aux_n];
      strcpy(Aux,aux);

      if      (type == COMPUTE_UV)            strcat(Aux,",computeUV");
      else if (type == COMPUTE_AV)            strcat(Aux,",computeAV");
      else if (type == COMPUTE_TMAV)          strcat(Aux,",computeTmAV");
      else if (type == COMPUTE_TMCAV)         strcat(Aux,",computeTmcAV");
      else if (type == COMPUTE_VUV)           strcat(Aux,",computeVUV");
      else if (type == COMPUTE_COARSE_CLOVER) strcat(Aux,",computeCoarseClover");
      else if (type == COMPUTE_REVERSE_Y)     strcat(Aux,",computeYreverse");
      else if (type == COMPUTE_COARSE_LOCAL)  strcat(Aux,",computeCoarseLocal");
      else if (type == COMPUTE_DIAGONAL)      strcat(Aux,",computeCoarseDiagonal");
      else if (type == COMPUTE_TMDIAGONAL)    strcat(Aux,",computeCoarseTmDiagonal");
      else errorQuda("Unknown type=%d\n", type);

      if (type == COMPUTE_UV || type == COMPUTE_VUV) {
	if      (dim == 0) strcat(Aux,",dim=0");
	else if (dim == 1) strcat(Aux,",dim=1");
	else if (dim == 2) strcat(Aux,",dim=2");
	else if (dim == 3) strcat(Aux,",dim=3");

	if (dir == QUDA_BACKWARDS) strcat(Aux,",dir=back");
	else if (dir == QUDA_FORWARDS) strcat(Aux,",dir=fwd");
      }

      if (type == COMPUTE_VUV || type == COMPUTE_COARSE_CLOVER) {
	strcat(Aux,meta.Location()==QUDA_CUDA_FIELD_LOCATION ? ",GPU," : ",CPU,");
	strcat(Aux,"coarse_vol=");
	strcat(Aux,X.VolString());
      } else {
	strcat(Aux,meta.Location()==QUDA_CUDA_FIELD_LOCATION ? ",GPU" : ",CPU");
      }

      return TuneKey(meta.VolString(), typeid(*this).name(), Aux);
    }

    void preTune() {
      switch (type) {
      case COMPUTE_VUV:
	Y.backup();
	Xinv.backup();
      case COMPUTE_COARSE_LOCAL:
      case COMPUTE_DIAGONAL:
      case COMPUTE_TMDIAGONAL:
      case COMPUTE_COARSE_CLOVER:
	X.backup();
      case COMPUTE_UV:
      case COMPUTE_AV:
      case COMPUTE_TMAV:
      case COMPUTE_TMCAV:
      case COMPUTE_REVERSE_Y:
	break;
      default:
	errorQuda("Undefined compute type %d", type);
      }
    }

    void postTune() {
      switch (type) {
      case COMPUTE_VUV:
	Y.restore();
	Xinv.restore();
      case COMPUTE_COARSE_LOCAL:
      case COMPUTE_DIAGONAL:
      case COMPUTE_TMDIAGONAL:
      case COMPUTE_COARSE_CLOVER:
	X.restore();
      case COMPUTE_UV:
      case COMPUTE_AV:
      case COMPUTE_TMAV:
      case COMPUTE_TMCAV:
      case COMPUTE_REVERSE_Y:
	break;
      default:
	errorQuda("Undefined compute type %d", type);
      }
    }
  };


  template <typename Flloat, typename Gauge, int n>
  struct CalculateYhatArg {
    Gauge Yhat;
    const Gauge Y;
    const Gauge Xinv;
    int dim[QUDA_MAX_DIM];
    int comm_dim[QUDA_MAX_DIM];
    int nFace;
    const int coarseVolumeCB;   /** Coarse grid volume */

    CalculateYhatArg(const Gauge &Yhat, const Gauge Y, const Gauge Xinv, const int *dim, const int *comm_dim, int nFace)
      : Yhat(Yhat), Y(Y), Xinv(Xinv), nFace(nFace), coarseVolumeCB(Y.VolumeCB()) {
      for (int i=0; i<4; i++) {
	this->comm_dim[i] = comm_dim[i];
	this->dim[i] = dim[i];
      }
    }
  };

  template<typename Float, int n, typename Arg>
  __device__ __host__ void computeYhat(Arg &arg, int d, int x_cb, int parity, int i) {

    int coord[5];
    getCoords(coord, x_cb, arg.dim, parity);
    coord[4] = 0;

    const int ghost_idx = ghostFaceIndex<0>(coord, arg.dim, d, arg.nFace);

    // first do the backwards links Y^{+\mu} * X^{-\dagger}
    if ( arg.comm_dim[d] && (coord[d] - arg.nFace < 0) ) {

      for(int j = 0; j<n; j++) {
	arg.Yhat.Ghost(d,1-parity,ghost_idx,i,j) = 0.0;
	for(int k = 0; k<n; k++) {
	  arg.Yhat.Ghost(d,1-parity,ghost_idx,i,j) += arg.Y.Ghost(d,1-parity,ghost_idx,i,k) * conj(arg.Xinv(0,parity,x_cb,j,k));
	}
      }

    } else {
      const int back_idx = linkIndexM1(coord, arg.dim, d);

      for(int j = 0; j<n; j++) {
	arg.Yhat(d,1-parity,back_idx,i,j) = 0.0;
	for(int k = 0; k<n; k++) {
	  arg.Yhat(d,1-parity,back_idx,i,j) += arg.Y(d,1-parity,back_idx,i,k) * conj(arg.Xinv(0,parity,x_cb,j,k));
	}
      }

    }

    // now do the forwards links X^{-1} * Y^{-\mu}
    for(int j = 0; j<n; j++) {
      arg.Yhat(d+4,parity,x_cb,i,j) = 0.0;
      for(int k = 0; k<n; k++) {
	arg.Yhat(d+4,parity,x_cb,i,j) += arg.Xinv(0,parity,x_cb,i,k) * arg.Y(d+4,parity,x_cb,k,j);
      }
    }

  }

  template<typename Float, int n, typename Arg>
  void CalculateYhatCPU(Arg &arg) {

    for (int d=0; d<4; d++) {
      for (int parity=0; parity<2; parity++) {
	for (int x_cb=0; x_cb<arg.Y.VolumeCB(); x_cb++) {
	  for (int i=0; i<n; i++) computeYhat<Float,n>(arg, d, x_cb, parity, i);
	} // x_cb
      } //parity
    } // dimension
  }

  template<typename Float, int n, typename Arg>
  __global__ void CalculateYhatGPU(Arg arg) {
    int x_cb = blockDim.x*blockIdx.x + threadIdx.x;
    if (x_cb >= arg.coarseVolumeCB) return;
    int i_parity = blockDim.y*blockIdx.y + threadIdx.y;
    if (i_parity >= 2*n) return;
    int d = blockDim.z*blockIdx.z + threadIdx.z;
    if (d >= 4) return;

    int i = i_parity % n;
    int parity = i_parity / n;
    // first do the backwards links Y^{+\mu} * X^{-\dagger}
    computeYhat<Float,n>(arg, d, x_cb, parity, i);
  }

  template <typename Float, int n, typename Arg>
  class CalculateYhat : public TunableVectorYZ {

  protected:
    Arg &arg;
    const LatticeField &meta;

    long long flops() const { return 2l * arg.coarseVolumeCB * 8 * n * n * (8*n-2); } // 8 from dir, 8 from complexity,
    long long bytes() const { return 2l * (arg.Xinv.Bytes() + 8*arg.Y.Bytes() + 8*arg.Yhat.Bytes()); }

    unsigned int minThreads() const { return arg.coarseVolumeCB; }

    bool tuneGridDim() const { return false; } // don't tune the grid dimension

  public:
    CalculateYhat(Arg &arg, const LatticeField &meta) : TunableVectorYZ(2*n,4), arg(arg), meta(meta)
    {
      strcpy(aux,comm_dim_partitioned_string());
    }
    virtual ~CalculateYhat() { }

    void apply(const cudaStream_t &stream) {
      TuneParam tp = tuneLaunch(*this, getTuning(), getVerbosity());
      if (meta.Location() == QUDA_CPU_FIELD_LOCATION) {
	CalculateYhatCPU<Float,n,Arg>(arg);
      } else {
	CalculateYhatGPU<Float,n,Arg> <<<tp.grid,tp.block,tp.shared_bytes>>>(arg);
      }
    }

    bool advanceTuneParam(TuneParam &param) const {
      if (meta.Location() == QUDA_CUDA_FIELD_LOCATION) return Tunable::advanceTuneParam(param);
      else return false;
    }

    TuneKey tuneKey() const {
      char Aux[TuneKey::aux_n];
      strcpy(Aux,aux);
      strcat(Aux,meta.Location()==QUDA_CUDA_FIELD_LOCATION ? ",GPU" : ",CPU");
      return TuneKey(meta.VolString(), typeid(*this).name(), Aux);
    }
  };


  /**
     @brief Calculate the coarse-link field, include the clover field,
     and its inverse, and finally also compute the preconditioned
     coarse link field.

     @param Y[out] Coarse link field accessor
     @param X[out] Coarse clover field accessor
     @param Xinv[out] Coarse clover inverse field accessor
     @param UV[out] Temporary accessor used to store fine link field * null space vectors
     @param AV[out] Temporary accessor use to store fine clover inverse * null
     space vectors (only applicable when fine-grid operator is the
     preconditioned clover operator else in general this just aliases V
     @param V[in] Packed null-space vector accessor
     @param G[in] Fine grid link / gauge field accessor
     @param C[in] Fine grid clover field accessor
     @param Cinv[in] Fine grid clover inverse field accessor
     @param Y_[out] Coarse link field
     @param X_[out] Coarse clover field
     @param Xinv_[out] Coarse clover field
     @param Yhat_[out] Preconditioned coarse link field
     @param v[in] Packed null-space vectors
     @param kappa[in] Kappa parameter
     @param mu[in] Twisted-mass parameter
     @param matpc[in] The type of preconditioning of the source fine-grid operator
   */
  template<bool from_coarse, typename Float, int fineSpin, int fineColor, int coarseSpin, int coarseColor,
	   QudaGaugeFieldOrder gOrder, typename F, typename Ftmp, typename coarseGauge, typename fineGauge, typename fineClover>
  void calculateY(coarseGauge &Y, coarseGauge &X, coarseGauge &Xinv, Ftmp &UV, F &AV, F &V, fineGauge &G, fineClover &C, fineClover &Cinv,
		  GaugeField &Y_, GaugeField &X_, GaugeField &Xinv_, GaugeField &Yhat_, ColorSpinorField &av, const ColorSpinorField &v,
		  double kappa, double mu, double mu_factor, QudaDiracType dirac, QudaMatPCType matpc) {

    // sanity checks
    if (matpc == QUDA_MATPC_EVEN_EVEN_ASYMMETRIC || matpc == QUDA_MATPC_ODD_ODD_ASYMMETRIC)
      errorQuda("Unsupported coarsening of matpc = %d", matpc);

    bool is_dirac_coarse = (dirac == QUDA_COARSE_DIRAC || dirac == QUDA_COARSEPC_DIRAC) ? true : false;
    if (is_dirac_coarse && fineSpin != 2)
      errorQuda("Input Dirac operator %d should have nSpin=2, not nSpin=%d\n", dirac, fineSpin);
    if (!is_dirac_coarse && fineSpin != 4)
      errorQuda("Input Dirac operator %d should have nSpin=4, not nSpin=%d\n", dirac, fineSpin);
    if (!is_dirac_coarse && fineColor != 3)
      errorQuda("Input Dirac operator %d should have nColor=3, not nColor=%d\n", dirac, fineColor);

    if (G.Ndim() != 4) errorQuda("Number of dimensions not supported");
    const int nDim = 4;

    int x_size[5];
    for (int i=0; i<4; i++) x_size[i] = v.X(i);
    x_size[4] = 1;

    int xc_size[5];
    for (int i=0; i<4; i++) xc_size[i] = X_.X()[i];
    xc_size[4] = 1;

    int geo_bs[QUDA_MAX_DIM];
    for(int d = 0; d < nDim; d++) geo_bs[d] = x_size[d]/xc_size[d];
    int spin_bs = V.Nspin()/Y.NspinCoarse();

    //Calculate UV and then VUV for each dimension, accumulating directly into the coarse gauge field Y

    typedef CalculateYArg<Float,coarseGauge,fineGauge,F,Ftmp,fineClover> Arg;
    Arg arg(Y, X, Xinv, UV, AV, G, V, C, Cinv, kappa, mu, mu_factor, x_size, xc_size, geo_bs, spin_bs);
    CalculateY<from_coarse, Float, fineSpin, fineColor, coarseSpin, coarseColor, Arg> y(arg, dirac, v, Y_, X_, Xinv_);

    QudaFieldLocation location = checkLocation(Y_, X_, Xinv_, Yhat_, av, v);
    printfQuda("Running link coarsening on the %s\n", location == QUDA_CUDA_FIELD_LOCATION ? "GPU" : "CPU");

    // If doing a preconditioned operator with a clover term then we
    // have bi-directional links, though we can do the bidirectional setup for all operators for debugging
    bool bidirectional_links = (dirac == QUDA_CLOVERPC_DIRAC || dirac == QUDA_COARSEPC_DIRAC || bidirectional_debug ||
				dirac == QUDA_TWISTED_MASSPC_DIRAC || dirac == QUDA_TWISTED_CLOVERPC_DIRAC);
    if (bidirectional_links) printfQuda("Doing bi-directional link coarsening\n");
    else printfQuda("Doing uni-directional link coarsening\n");

    printfQuda("V2 = %e\n", V.norm2());

    // do exchange of null-space vectors
    const int nFace = 1;
    v.exchangeGhost(QUDA_INVALID_PARITY, nFace, 0);
    arg.V.resetGhost(v.Ghost());  // point the accessor to the correct ghost buffer
    if (&v == &av) arg.AV.resetGhost(av.Ghost());
    LatticeField::bufferIndex = (1 - LatticeField::bufferIndex); // update ghost bufferIndex for next exchange

    // If doing preconditioned clover then we first multiply the
    // null-space vectors by the clover inverse matrix, since this is
    // needed for the coarse link computation
    if ( dirac == QUDA_CLOVERPC_DIRAC && (matpc == QUDA_MATPC_EVEN_EVEN || matpc == QUDA_MATPC_ODD_ODD) ) {
      printfQuda("Computing AV\n");

      y.setComputeType(COMPUTE_AV);
      y.apply(0);

      printfQuda("AV2 = %e\n", AV.norm2());
    }

    // If doing preconditioned twisted-mass then we first multiply the
    // null-space vectors by the inverse twist, since this is
    // needed for the coarse link computation
    if ( dirac == QUDA_TWISTED_MASSPC_DIRAC && (matpc == QUDA_MATPC_EVEN_EVEN || matpc == QUDA_MATPC_ODD_ODD) ) {
      printfQuda("Computing TMAV\n");

      y.setComputeType(COMPUTE_TMAV);
      y.apply(0);

      printfQuda("AV2 = %e\n", AV.norm2());
    }

    // If doing preconditioned twisted-clover then we first multiply the
    // null-space vectors by the inverse of the squared clover matrix plus
    // mu^2, and then we multiply the result by the clover matrix. This is
    // needed for the coarse link computation
    if ( dirac == QUDA_TWISTED_CLOVERPC_DIRAC && (matpc == QUDA_MATPC_EVEN_EVEN || matpc == QUDA_MATPC_ODD_ODD) ) {
      printfQuda("Computing TMCAV\n");

      y.setComputeType(COMPUTE_TMCAV);
      y.apply(0);

      printfQuda("AV2 = %e\n", AV.norm2());
    }

    // First compute the coarse forward links if needed
    if (bidirectional_links) {
      for (int d = 0; d < nDim; d++) {
	y.setDimension(d);
	y.setDirection(QUDA_FORWARDS);
	printfQuda("Computing forward %d UV and VUV\n", d);

	y.setComputeType(COMPUTE_UV);  // compute U*V product
	y.apply(0);
	printfQuda("UV2[%d] = %e\n", d, UV.norm2());

	y.setComputeType(COMPUTE_VUV); // compute Y += VUV
	y.apply(0);
	printfQuda("Y2[%d] = %e\n", d, Y.norm2(4+d));
      }
    }

    if ( (dirac == QUDA_CLOVERPC_DIRAC || dirac == QUDA_TWISTED_MASSPC_DIRAC || dirac == QUDA_TWISTED_CLOVERPC_DIRAC) &&
	 (matpc == QUDA_MATPC_EVEN_EVEN || matpc == QUDA_MATPC_ODD_ODD) ) {
      av.exchangeGhost(QUDA_INVALID_PARITY, nFace, 0);
      arg.AV.resetGhost(av.Ghost());  // make sure we point to the correct pointer in the accessor
      LatticeField::bufferIndex = (1 - LatticeField::bufferIndex); // update ghost bufferIndex for next exchange
    }

    // Now compute the backward links
    for (int d = 0; d < nDim; d++) {
      y.setDimension(d);
      y.setDirection(QUDA_BACKWARDS);
      printfQuda("Computing backward %d UV and VUV\n", d);

      y.setComputeType(COMPUTE_UV);  // compute U*A*V product
      y.apply(0);
      printfQuda("UAV2[%d] = %e\n", d, UV.norm2());

      y.setComputeType(COMPUTE_VUV); // compute Y += VUV
      y.apply(0);
      printfQuda("Y2[%d] = %e\n", d, Y.norm2(d));
    }
    printfQuda("X2 = %e\n", X.norm2(0));

    cudaDeviceSynchronize(); checkCudaError();

    // if not doing a preconditioned operator then we can trivially
    // construct the forward links from the backward links
    if ( !bidirectional_links ) {
      printfQuda("Reversing links\n");
      y.setComputeType(COMPUTE_REVERSE_Y);  // reverse the links for the forwards direction
      y.apply(0);
    }

    cudaDeviceSynchronize(); checkCudaError();

    printfQuda("Computing coarse local\n");
    y.setComputeType(COMPUTE_COARSE_LOCAL);
    y.apply(0);
    printfQuda("X2 = %e\n", X.norm2(0));

    cudaDeviceSynchronize(); checkCudaError();

    // Check if we have a clover term that needs to be coarsened
    if (dirac == QUDA_CLOVER_DIRAC || dirac == QUDA_COARSE_DIRAC || dirac == QUDA_TWISTED_CLOVER_DIRAC) {
      printfQuda("Computing fine->coarse clover term\n");
      y.setComputeType(COMPUTE_COARSE_CLOVER);
      y.apply(0);
    } else {  //Otherwise, we just have to add the identity matrix
      printfQuda("Summing diagonal contribution to coarse clover\n");
      y.setComputeType(COMPUTE_DIAGONAL);
      y.apply(0);
    }

    cudaDeviceSynchronize(); checkCudaError();

    if (arg.mu*arg.mu_factor!=0 || dirac == QUDA_TWISTED_MASS_DIRAC || dirac == QUDA_TWISTED_CLOVER_DIRAC) {
      if (dirac == QUDA_TWISTED_MASS_DIRAC || dirac == QUDA_TWISTED_CLOVER_DIRAC)
	arg.mu_factor += 1.;
      printfQuda("Adding mu = %e\n",arg.mu*arg.mu_factor);
      y.setComputeType(COMPUTE_TMDIAGONAL);
      y.apply(0);
    }

    cudaDeviceSynchronize(); checkCudaError();

    printfQuda("X2 = %e\n", X.norm2(0));

    // invert the clover matrix field
    const int n = X_.Ncolor();
    if (X_.Location() == QUDA_CUDA_FIELD_LOCATION && X_.Order() == QUDA_FLOAT2_GAUGE_ORDER) {
      GaugeFieldParam param(X_);
      // need to copy into AoS format for MAGMA
      param.order = QUDA_MILC_GAUGE_ORDER;
      cudaGaugeField X(param);
      cudaGaugeField Xinv(param);
      X.copy(X_);
      blas::flops += cublas::BatchInvertMatrix((void*)Xinv.Gauge_p(), (void*)X.Gauge_p(), n, X.Volume(), X_.Precision(), X.Location());
      Xinv_.copy(Xinv);
    } else if (X_.Location() == QUDA_CPU_FIELD_LOCATION && X_.Order() == QUDA_QDP_GAUGE_ORDER) {
      cpuGaugeField *X_h = static_cast<cpuGaugeField*>(&X_);
      cpuGaugeField *Xinv_h = static_cast<cpuGaugeField*>(&Xinv_);
      blas::flops += cublas::BatchInvertMatrix(((void**)Xinv_h->Gauge_p())[0], ((void**)X_h->Gauge_p())[0], n, X_h->Volume(), X_.Precision(), QUDA_CPU_FIELD_LOCATION);
    } else {
      errorQuda("Unsupported location=%d and order=%d", X_.Location(), X_.Order());
    }

    // now exchange Y halos of both forwards and backwards links for multi-process dslash
    Y_.exchangeGhost(QUDA_LINK_BIDIRECTIONAL);

    // compute the preconditioned links
    // Yhat_back(x-\mu) = Y_back(x-\mu) * Xinv^dagger(x) (positive projector)
    // Yhat_fwd(x) = Xinv(x) * Y_fwd(x)                  (negative projector)
    {
      // use spin-ignorant accessor to make multiplication simpler
      // also with new accessor we ensure we're accessing the same ghost buffer in Y_ as was just exchanged
      typedef typename gauge::FieldOrder<Float,coarseColor*coarseSpin,1,gOrder> gCoarse;
      gCoarse yAccessor(const_cast<GaugeField&>(Y_));
      gCoarse yHatAccessor(const_cast<GaugeField&>(Yhat_));
      gCoarse xInvAccessor(const_cast<GaugeField&>(Xinv_));
      printfQuda("Xinv = %e\n", xInvAccessor.norm2(0));

      int comm_dim[4];
      for (int i=0; i<4; i++) comm_dim[i] = comm_dim_partitioned(i);
      typedef CalculateYhatArg<Float,gCoarse,coarseSpin*coarseColor> yHatArg;
      yHatArg arg(yHatAccessor, yAccessor, xInvAccessor, xc_size, comm_dim, 1);
      CalculateYhat<Float, coarseSpin*coarseColor, yHatArg> yHat(arg, Y_);
      yHat.apply(0);

      for (int d=0; d<8; d++) printfQuda("Yhat[%d] = %e\n", d, Y.norm2(d));
    }

    // fill back in the bulk of Yhat so that the backward link is updated on the previous node
    // need to put this in the bulk of the previous node - but only send backwards the backwards links to and not overwrite the forwards bulk
    Yhat_.injectGhost(QUDA_LINK_BACKWARDS);

    // exchange forwards links for multi-process dslash dagger
    // need to put this in the ghost zone of the next node - but only send forwards the forwards links and not overwrite the backwards ghost
    Yhat_.exchangeGhost(QUDA_LINK_FORWARDS);

  }



} // namespace quda
