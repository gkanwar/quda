/**
   Driver for generic blas routine with four loads and two store.
 */
template <int NXZ, template < int MXZ, typename Float, typename FloatN> class Functor,
  typename write, typename T>
  void multiblasCuda(const coeff_array<T> &a, const coeff_array<T> &b, const coeff_array<T> &c,
		     CompositeColorSpinorField &x, CompositeColorSpinorField &y,
		     CompositeColorSpinorField &z, CompositeColorSpinorField &w) {

  if (checkLocation(*x[0], *y[0], *z[0], *w[0]) == QUDA_CUDA_FIELD_LOCATION) {

    if (y[0]->Precision() == QUDA_DOUBLE_PRECISION && x[0]->Precision() == QUDA_DOUBLE_PRECISION) {

#if defined(GPU_WILSON_DIRAC) || defined(GPU_DOMAIN_WALL_DIRAC) || defined(GPU_STAGGERED_DIRAC)
      const int M = 1;
      multiblasCuda<NXZ,double2,double2,double2,M,Functor,write>(a,b,c,x,y,z,w,x[0]->Length()/(2*M));
#else
      errorQuda("blas has not been built for Nspin=%d fields", x[0]->Nspin());
#endif

    } else if (y[0]->Precision() == QUDA_SINGLE_PRECISION && x[0]->Precision() == QUDA_SINGLE_PRECISION) {

      if (x[0]->Nspin() == 4) {
#if defined(GPU_WILSON_DIRAC) || defined(GPU_DOMAIN_WALL_DIRAC)
	const int M = 1;
	multiblasCuda<NXZ,float4,float4,float4,M,Functor,write>(a,b,c,x,y,z,w,x[0]->Length()/(4*M));
#else
	errorQuda("blas has not been built for Nspin=%d fields", x[0]->Nspin());
#endif

      } else if (x[0]->Nspin()==2 || x[0]->Nspin()==1) {

#if defined(GPU_WILSON_DIRAC) || defined(GPU_DOMAIN_WALL_DIRAC) || defined(GPU_STAGGERED_DIRAC)
	const int M = 1;
	multiblasCuda<NXZ,float2,float2,float2,M,Functor,write>(a,b,c,x,y,z,w,x[0]->Length()/(2*M));
#else
	errorQuda("blas has not been built for Nspin=%d fields", x[0]->Nspin());
#endif
      } else { errorQuda("nSpin=%d is not supported\n", x[0]->Nspin()); }

    } else if (y[0]->Precision() == QUDA_HALF_PRECISION && x[0]->Precision() == QUDA_HALF_PRECISION) {

      if (x[0]->Ncolor() != 3) { errorQuda("nColor = %d is not supported", x[0]->Ncolor()); }
      if (x[0]->Nspin() == 4) { //wilson
#if defined(GPU_WILSON_DIRAC) || defined(GPU_DOMAIN_WALL_DIRAC)
	const int M = 6;
	multiblasCuda<NXZ,float4,short4,short4,M,Functor,write>(a,b,c,x,y,z,w,x[0]->Volume());
#else
	errorQuda("blas has not been built for Nspin=%d fields", x[0]->Nspin());
#endif
      } else if (x[0]->Nspin() == 1) {//staggered
#ifdef GPU_STAGGERED_DIRAC
	const int M = 3;
	multiblasCuda<NXZ,float2,short2,short2,M,Functor,write>(a,b,c,x,y,z,w,x[0]->Volume());
#else
	errorQuda("blas has not been built for Nspin=%d fields", x[0]->Nspin());
#endif
      } else {
	errorQuda("nSpin=%d is not supported\n", x[0]->Nspin());
      }

    } else {

      errorQuda("Precision combination x=%d not supported\n", x[0]->Precision());

    }
  } else { // fields on the cpu
    // using namespace quda::colorspinor;
    // if (x[0]->Precision() == QUDA_DOUBLE_PRECISION) {
    //   Functor<NXZ, NYW, double2, double2> f(a, b, c);
    //   genericMultBlas<double, double, writeX, writeY, writeZ, writeW>(x, y, z, w, f);
    // } else if (x[0]->Precision() == QUDA_SINGLE_PRECISION) {
    //   Functor<NXZ, NYW, float2, float2> f(a, make_float2(b.x,b.y), make_float2(c.x,c.y) );
    //   genericMultBlas<float, float, writeX, writeY, writeZ, writeW>(x, y, z, w, f);
    // } else {
      errorQuda("Not implemented");
    // }
  }

}
