set -x 

lpips_lambda=0.8

image_size=128
image_size_encoder=224

patch_size=14

batch_size=1
num_samples=1

dataset_name=ffhq


DATASET_FLAGS="
 --data_dir /mnt/yslan/datasets/cache/lmdb_debug/${dataset_name} \
"

lr=2e-5 # for improved-diffusion unet
kl_lambda=0
vit_lr=1e-5 # for improved-diffusion unet

encoder_lr=$vit_lr
vit_decoder_lr=$vit_lr
conv_lr=0.0005
triplane_decoder_lr=$conv_lr
super_resolution_lr=$conv_lr

scale_clip_encoding=18.4
triplane_scaling_divider=1

CKPT_FLAGS="
--resume_checkpoint checkpoints/ffhq/model_joint_denoise_rec_model1580000.pt \
"

LR_FLAGS="--encoder_lr $encoder_lr \
--vit_decoder_lr $vit_decoder_lr \
--triplane_decoder_lr $triplane_decoder_lr \
--super_resolution_lr $super_resolution_lr \
--lr $lr"

TRAIN_FLAGS="--iterations 10001 --anneal_lr False \
 --batch_size $batch_size --save_interval 10000 \
 --image_size_encoder $image_size_encoder \
 --image_size $image_size \
 --dino_version v2 \
 --sr_training False \
 --cls_token False \
 --weight_decay 0.05 \
 --image_size $image_size \
 --kl_lambda ${kl_lambda} \
 --no_dim_up_mlp True \
 --uvit_skip_encoder True \
 --fg_mse True \
 --bg_lamdba 0.01 \
 "
#  --vae_p 1 \


DDPM_MODEL_FLAGS="
--learn_sigma False \
--num_heads 8 \
--num_res_blocks 2 \
--num_channels 320 \
--attention_resolutions "4,2,1" \
--use_spatial_transformer True \
--transformer_depth 1 \
--context_dim 768 \
"


DIFFUSION_FLAGS="--diffusion_steps 1000 --noise_schedule linear \
--use_kl False \
--use_amp False \
--triplane_scaling_divider ${triplane_scaling_divider} \
--trainer_name vpsde_crossattn \
--mixed_prediction True \
--denoise_in_channels 12 \
--denoise_out_channels 12 \
--diffusion_input_size 32 \
--p_rendering_loss False \
--pred_type v \
--predict_v True \
"

DDIM_FLAGS="
--timestep_respacing ddim250 \
--use_ddim True \
--unconditional_guidance_scale 6.5 \
"

# not used here
CONTROL_FLAGS="
--train_vae False \
--create_controlnet False \
--control_key img_sr \
"

prompt="a middle aged woman with brown hair, wearing glasses." 

logdir="./logs/LSGM/inference/t23d/${dataset_name}/crossattn-v1-ddim250/T23D_test/woman_glass-newcls"

SR_TRAIN_FLAGS_v1_2XC="
--decoder_in_chans 32 \
--out_chans 96 \
--alpha_lambda 1 \
--logdir $logdir \
--arch_encoder vits \
--arch_decoder vitb \
--vit_decoder_wd 0.001 \
--encoder_weight_decay 0.001 \
--color_criterion mse \
--triplane_in_chans 32 \
--decoder_output_dim 32 \
--ae_classname vit.vit_triplane.VAE_LDM_V4_vit3D_v3_conv3D_depth2_xformer_mha_PEinit_2d_sincos_uvit_RodinRollOutConv_4x4_lite_mlp_unshuffle_4XC_final \
"

SR_TRAIN_FLAGS=${SR_TRAIN_FLAGS_v1_2XC}

NUM_GPUS=1

rm -rf "$logdir"/runs
mkdir -p "$logdir"/
cp "$0" "$logdir"/

export OMP_NUM_THREADS=12
export NCCL_ASYNC_ERROR_HANDLING=1
export CUDA_VISIBLE_DEVICES=6

torchrun --nproc_per_node=$NUM_GPUS \
  --master_port=0 \
  --rdzv_backend=c10d \
  --rdzv-endpoint=localhost:33385 \
  --nnodes 1 \
 scripts/vit_triplane_diffusion_sample.py \
 --num_workers 4 \
 --depth_lambda 0 \
 ${TRAIN_FLAGS}  \
 ${SR_TRAIN_FLAGS} \
 ${DIFFUSION_FLAGS} \
 ${CONTROL_FLAGS} \
 ${DDPM_MODEL_FLAGS} \
 ${DATASET_FLAGS} \
 ${CKPT_FLAGS} \
 ${LR_FLAGS} \
 --lpips_lambda $lpips_lambda \
 --overfitting False \
 --load_pretrain_encoder True \
 --iterations 5000001 \
 --save_interval 10000 \
 --eval_interval 2500 \
 --decomposed True \
 --logdir $logdir \
 --cfg ffhq \
 --patch_size ${patch_size} \
 --eval_batch_size ${batch_size} \
 --prompt "$prompt" \
 --interval 5 \
 --save_img True \
 --num_samples ${num_samples} \
 --use_train_trajectory False \
 --normalize_clip_encoding True \
 --scale_clip_encoding ${scale_clip_encoding} \
 --overwrite_diff_inp_size 16 \
 --use_lmdb True \
 ${DDIM_FLAGS} \