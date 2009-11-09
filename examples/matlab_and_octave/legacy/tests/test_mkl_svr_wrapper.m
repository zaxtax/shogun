cache_size=50;
C=1;
svm_eps=1e-5;
mkl_eps=1e-6;
svm_tube=0.01;

kernels={};

global lpenv ;
if isempty(lpenv)|lpenv==0,
 lpenv=cplex_license(0) ;
end ;

% Kernel width for the 5 "basic" SVMs
rbf_width(1) = 0.005;
rbf_width(2) = 0.05;
rbf_width(3) = 0.5;
rbf_width(4) = 1;
rbf_width(5) = 10;
rand('state',0);
%rand('state',sum(100*clock));
f = [0.1:0.2:5];   % values for the different frequencies
no_obs = 1000;     % number of observations
kk=4;
traindat = [1:(((10*2*pi)-1)/(no_obs-1)):10*2*pi];
trainlab = sin(f(kk)*traindat);
testdat = [1:(((10*2*pi)-1)/(no_obs-1)):10*2*pi];
testlab = sin(f(kk)*traindat);

sg('send_command', 'new_svm LIBSVR');
%sg('send_command', 'new_svm SVRLIGHT');
sg('send_command', 'clean_features TRAIN' );
sg('set_features','TRAIN', traindat);
sg('set_labels', 'TRAIN', trainlab);
sg('send_command', sprintf('set_kernel GAUSSIAN REAL %d %f', cache_size, rbf_width(1)));
sg('send_command', 'init_kernel TRAIN');
kernels{1}=sg('get_kernel_matrix');

sg('set_features','TRAIN', traindat);
sg('send_command', sprintf('set_kernel GAUSSIAN REAL %d %f', cache_size, rbf_width(2)));
sg('send_command', 'init_kernel TRAIN');
kernels{2}=sg('get_kernel_matrix');

sg('set_features','TRAIN', traindat);
sg('send_command', sprintf('set_kernel GAUSSIAN REAL %d %f', cache_size, rbf_width(3)));
sg('send_command', 'init_kernel TRAIN');
kernels{3}=sg('get_kernel_matrix');

sg('set_features','TRAIN', traindat);
sg('send_command', sprintf('set_kernel GAUSSIAN REAL %d %f', cache_size, rbf_width(4)));
sg('send_command', 'init_kernel TRAIN');
kernels{4}=sg('get_kernel_matrix');

sg('set_features','TRAIN', traindat);
sg('send_command', sprintf('set_kernel GAUSSIAN REAL %d %f', cache_size, rbf_width(5)));
sg('send_command', 'init_kernel TRAIN');
kernels{5}=sg('get_kernel_matrix');

sg('send_command', 'clean_features TRAIN' );
sg('add_features','TRAIN', traindat);
sg('add_features','TRAIN', traindat);
sg('add_features','TRAIN', traindat);
sg('add_features','TRAIN', traindat);
sg('add_features','TRAIN', traindat);
sg('send_command', sprintf('set_kernel COMBINED %d', cache_size));
sg('send_command', sprintf('add_kernel 1 GAUSSIAN REAL %d %f', cache_size, rbf_width(1)));
sg('send_command', sprintf('add_kernel 1 GAUSSIAN REAL %d %f', cache_size, rbf_width(2)));
sg('send_command', sprintf('add_kernel 1 GAUSSIAN REAL %d %f', cache_size, rbf_width(3)));
sg('send_command', sprintf('add_kernel 1 GAUSSIAN REAL %d %f', cache_size, rbf_width(4)));
sg('send_command', sprintf('add_kernel 1 GAUSSIAN REAL %d %f', cache_size, rbf_width(5)));

sg('send_command', 'init_kernel TRAIN');
sg('send_command', 'use_mkl 0');
sg('send_command', 'loglevel ALL');
sg('send_command', 'use_precompute 0');
sg('send_command', 'mkl_parameters 1e-3 0');
sg('send_command', sprintf('c %f',C));
sg('send_command', sprintf('svm_epsilon %f',svm_eps));
sg('send_command', sprintf('svr_tube_epsilon %f',svm_tube));

betas=sg('get_subkernel_weights') ;
betas=betas/sum(betas(:)) ;
sg('set_subkernel_weights',betas) ;

sg('send_command', 'init_kernel TRAIN') ;
sg('send_command', sprintf('c %1.2e', C)) ;


OBJ=[] ;
thetas=[] ; sumbetas=[] ; A=[] ;

alpha_svmlight={};
b_svmlight=[];
beta_svmlight={};
obj_svmlight=[];
alpha_libsvm={};
b_libsvm=[];
beta_libsvm={};
obj_libsvm=[];

tic
for ii=1:100,
	% find most violated constraints
	% 1. compute optimal alphas
	sg('send_command', 'new_svm LIBSVR');
	%sg('send_command', 'new_svm SVRLIGHT');
	sg('send_command', 'svm_train');
	betas=sg('get_subkernel_weights') ;
	[b,alpha_idx]=sg('get_svm') ;
	alpha_svmlight{ii}=alpha_idx;
	b_svmlight(ii)=b;
	beta_svmlight{ii}=betas;
	obj_svmlight(ii)=sg('get_svm_objective');


	%sg('send_command', 'new_svm LIBSVR');
	sg('send_command', 'new_svm SVRLIGHT');
	sg('send_command', 'svm_train');
	betas=sg('get_subkernel_weights') ;
	[b,alpha_idx]=sg('get_svm') ;
	alpha_libsvm{ii}=alpha_idx;
	b_libsvm(ii)=b;
	beta_libsvm{ii}=betas;
	obj_libsvm(ii)=sg('get_svm_objective');

	obj_libsvm(ii)-obj_svmlight(ii)
	if abs(obj_libsvm(ii)-obj_svmlight(ii))>1e-3 | abs(b_libsvm(ii)-b_svmlight(ii))>1e-3,
		obj_libsvm(ii)
		obj_svmlight(ii)
		b_libsvm(ii)-b_svmlight(ii)
		b_libsvm(ii)
		b_svmlight(ii)
		keyboard
	end

	alphas=zeros(1,size(traindat,2)) ;
	alphas(alpha_idx(:,2)+1)=alpha_idx(:,1) ;

	% 2. compute current SVM objective
	OBJ(ii)=sg('get_svm_objective');

	sum_contrib=0;
	for i=1:5,
		contrib(i)=0.5*alphas*kernels{i}*alphas';
		sum_contrib=sum_contrib+contrib(i);
	end

	sum(abs(alphas))*svm_tube-alphas*trainlab'+sum_contrib
	const_contrib=sum(abs(alphas))*svm_tube-alphas*trainlab';
	for i=1:5,
		sumbetas(i)=const_contrib+contrib(i);
	end

	INF=1e20 ;
	A=[A; -sumbetas -1] ;
	f=[zeros(1,length(sumbetas)) 1] ;
	CA=[ones(1,length(sumbetas)) 0
		A] ;
	b=[1;zeros(size(A,1),1)] ;
	lb=[zeros(1,length(sumbetas)) -INF] ;
	ub=[ones(1,length(sumbetas)) INF] ;
	[res,lambda,how]=lp_solve(lpenv, f', sparse(CA), b, lb',ub',1,0) ;
	betas=reshape(res(1:end-1)',size(betas,1),size(betas,2)) ;
	thetas(ii)=-res(end) ;

	disp(sprintf('relative gap: %f',abs(1-thetas(end)/OBJ(end)))) ;
	betas
	if abs(1-thetas(end)/OBJ(end))<mkl_eps
		break
	end

	% update betas in gf
	sg('set_subkernel_weights',betas) ;
	sg('send_command', 'init_kernel TRAIN') ;
end
toc

sg('send_command', 'clean_features TEST' );
sg('add_features','TEST', testdat);
sg('add_features','TEST', testdat);
sg('add_features','TEST', testdat);
sg('add_features','TEST', testdat);
sg('add_features','TEST', testdat);
sg('set_labels', 'TEST', testlab);
sg('send_command', 'init_kernel TEST');
out2=sg('svm_classify');

sum(abs(testlab-out2))
sum((testlab-out2).^2)